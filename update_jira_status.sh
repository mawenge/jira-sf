#!/usr/bin/env bash
#
# update_jira_status.sh - transition a Jira issue to a new status from the
# command line.
#
# Designed to run in a macOS Terminal and compatible with the Bash 3.2 that
# ships with macOS. Requires curl and jq.

set -u

SCRIPT_NAME=$(basename "$0")
NEWLINE='
'

TICKET=""
STATUS=""
TOKEN=""
BASE_URL=""

HTTP_CODE=""
HTTP_BODY=""

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} --ticket <ISSUE-KEY> --status <STATUS> --token <TOKEN> --url <BASE-URL>

Transition a Jira issue to the requested status via Jira's REST API.

Required arguments:
  --ticket <ISSUE-KEY>   Jira issue key, e.g. KAN-4.
  --status <STATUS>      Destination status name, exactly as it appears in
                         Jira. Quote multi-word statuses, e.g.
                         --status "In Progress".
  --token <TOKEN>        API token. Sent as "Authorization: Bearer <token>".
  --url <BASE-URL>       Base URL of your Jira instance, e.g.
                         https://jira.example.com (no trailing path).

Options:
  -h, --help             Show this help text and exit.

Example:
  ${SCRIPT_NAME} --ticket KAN-4 --status "In Progress" \\
      --token "\$JIRA_TOKEN" --url https://jira.example.com

The script fetches the transitions currently available for the issue, picks
the one whose destination status matches --status exactly, and executes it.
If no available transition leads to the requested status, the available
destination statuses are listed and nothing is changed.
EOF
}

err() {
  printf '%s: error: %s\n' "$SCRIPT_NAME" "$1" >&2
}

fail_usage() {
  err "$1"
  printf "Run '%s --help' for usage.\n" "$SCRIPT_NAME" >&2
  exit 2
}

require_value() {
  # $1: option name, $2: number of remaining CLI arguments
  if [ "$2" -lt 2 ]; then
    fail_usage "option '$1' requires a value"
  fi
}

check_dependencies() {
  cmd=""
  for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "required command '$cmd' was not found in PATH. On macOS install it with: brew install $cmd"
      exit 3
    fi
  done
}

# http_request METHOD URL [JSON_PAYLOAD]
# On success sets HTTP_CODE and HTTP_BODY. Exits nonzero if curl itself fails
# (network error, DNS failure, TLS problem, ...).
http_request() {
  method=$1
  url=$2
  payload=${3:-}
  raw=""
  curl_exit=0

  if [ -n "$payload" ]; then
    raw=$(curl -sS -X "$method" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      --data "$payload" \
      -w "${NEWLINE}%{http_code}" \
      "$url" 2>&1)
    curl_exit=$?
  else
    raw=$(curl -sS -X "$method" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/json" \
      -w "${NEWLINE}%{http_code}" \
      "$url" 2>&1)
    curl_exit=$?
  fi

  if [ "$curl_exit" -ne 0 ]; then
    err "curl failed (exit code $curl_exit) for $method $url"
    if [ -n "$raw" ]; then
      printf '%s\n' "$raw" >&2
    fi
    exit 4
  fi

  HTTP_CODE=${raw##*"$NEWLINE"}
  HTTP_BODY=${raw%"$NEWLINE"*}
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --ticket)
      require_value "$1" "$#"
      TICKET=$2
      shift 2
      ;;
    --ticket=*)
      TICKET=${1#--ticket=}
      shift
      ;;
    --status)
      require_value "$1" "$#"
      STATUS=$2
      shift 2
      ;;
    --status=*)
      STATUS=${1#--status=}
      shift
      ;;
    --token)
      require_value "$1" "$#"
      TOKEN=$2
      shift 2
      ;;
    --token=*)
      TOKEN=${1#--token=}
      shift
      ;;
    --url)
      require_value "$1" "$#"
      BASE_URL=$2
      shift 2
      ;;
    --url=*)
      BASE_URL=${1#--url=}
      shift
      ;;
    -*)
      fail_usage "unknown option '$1'"
      ;;
    *)
      fail_usage "unexpected positional argument '$1' (all values must be passed with named options)"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

[ -n "$TICKET" ] || fail_usage "missing required option --ticket"
[ -n "$STATUS" ] || fail_usage "missing required option --status"
[ -n "$TOKEN" ] || fail_usage "missing required option --token"
[ -n "$BASE_URL" ] || fail_usage "missing required option --url"

case "$TICKET" in
  [A-Za-z]*-[0-9]*)
    ;;
  *)
    fail_usage "invalid --ticket '$TICKET' (expected a Jira issue key like ABC-123)"
    ;;
esac

case "$BASE_URL" in
  http://*|https://*)
    ;;
  *)
    fail_usage "invalid --url '$BASE_URL' (must start with http:// or https://)"
    ;;
esac

# Normalize one trailing slash on the base URL.
BASE_URL=${BASE_URL%/}

check_dependencies

# ---------------------------------------------------------------------------
# Resolve the transition that leads to the requested status
# ---------------------------------------------------------------------------

TRANSITIONS_URL="${BASE_URL}/rest/api/2/issue/${TICKET}/transitions"

http_request GET "$TRANSITIONS_URL"

case "$HTTP_CODE" in
  2[0-9][0-9])
    ;;
  *)
    err "Jira returned HTTP ${HTTP_CODE} when fetching available transitions for ${TICKET}."
    if [ -n "$HTTP_BODY" ]; then
      printf 'Response body:\n%s\n' "$HTTP_BODY" >&2
    fi
    printf 'Check the issue key, the base URL and that the token has permission to view the issue.\n' >&2
    exit 5
    ;;
esac

if ! printf '%s' "$HTTP_BODY" | jq -e . >/dev/null 2>&1; then
  err "Jira's response for ${TICKET} was not valid JSON; cannot resolve transitions."
  printf 'Check that --url points at the root of a Jira instance (received a non-JSON response).\n' >&2
  exit 6
fi

TRANSITION_ID=$(printf '%s' "$HTTP_BODY" \
  | jq -r --arg status "$STATUS" \
      '[.transitions[]? | select(.to.name == $status) | .id][0] // empty')

if [ -z "$TRANSITION_ID" ]; then
  err "no available transition moves ${TICKET} to status '${STATUS}'."
  AVAILABLE=$(printf '%s' "$HTTP_BODY" \
    | jq -r '[.transitions[]?.to.name] | if length == 0 then "  (none)" else (map("  - " + .) | join("\n")) end')
  printf 'Available destination statuses for %s:\n%s\n' "$TICKET" "$AVAILABLE" >&2
  printf 'Status names are case-sensitive and must match Jira exactly (quote multi-word names).\n' >&2
  exit 7
fi

# ---------------------------------------------------------------------------
# Execute the transition
# ---------------------------------------------------------------------------

PAYLOAD=$(jq -n --arg id "$TRANSITION_ID" '{transition: {id: $id}}')

http_request POST "$TRANSITIONS_URL" "$PAYLOAD"

case "$HTTP_CODE" in
  2[0-9][0-9])
    printf 'Success: %s transitioned to status '\''%s'\'' (transition id %s).\n' \
      "$TICKET" "$STATUS" "$TRANSITION_ID"
    exit 0
    ;;
  *)
    err "Jira returned HTTP ${HTTP_CODE} when executing transition ${TRANSITION_ID} for ${TICKET}."
    if [ -n "$HTTP_BODY" ]; then
      printf 'Response body:\n%s\n' "$HTTP_BODY" >&2
    fi
    printf 'The issue was not transitioned. Check permissions and any required transition fields.\n' >&2
    exit 8
    ;;
esac
