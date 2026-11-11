#!/usr/bin/env bash
#
# create_ticket.sh - Create a new Jira ticket (Task) in the KAN project.
#
# Usage:
#   ./create_ticket.sh "<summary>" "<description>"
#
# Required environment variables:
#   JIRA_EMAIL      - Jira account email for Basic authentication
#   JIRA_API_TOKEN  - Jira API token for Basic authentication

set -euo pipefail

JIRA_BASE_URL="https://wenge-sf.atlassian.net"
PROJECT_KEY="KAN"
ISSUE_TYPE="Task"

usage() {
    echo "Usage: $0 <summary> <description>" >&2
    echo "  Creates a Jira ${ISSUE_TYPE} in project ${PROJECT_KEY} at ${JIRA_BASE_URL}." >&2
    echo "  Requires JIRA_EMAIL and JIRA_API_TOKEN environment variables." >&2
}

if [ "$#" -ne 2 ]; then
    echo "Error: expected exactly 2 arguments (summary and description), got $#." >&2
    usage
    exit 1
fi

SUMMARY="$1"
DESCRIPTION="$2"

if [ -z "${JIRA_EMAIL:-}" ]; then
    echo "Error: JIRA_EMAIL environment variable is not set." >&2
    exit 1
fi

if [ -z "${JIRA_API_TOKEN:-}" ]; then
    echo "Error: JIRA_API_TOKEN environment variable is not set." >&2
    exit 1
fi

for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' is not installed." >&2
        exit 1
    fi
done

PAYLOAD=$(jq -n \
    --arg project "$PROJECT_KEY" \
    --arg issuetype "$ISSUE_TYPE" \
    --arg summary "$SUMMARY" \
    --arg description "$DESCRIPTION" \
    '{
        fields: {
            project: { key: $project },
            issuetype: { name: $issuetype },
            summary: $summary,
            description: $description
        }
    }')

curl --silent --show-error --fail-with-body \
    --request POST \
    --user "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "$PAYLOAD" \
    "${JIRA_BASE_URL}/rest/api/2/issue"
