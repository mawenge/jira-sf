# jira-sf

Command-line tooling for Jira automation.

## update_jira_status.sh

A Bash script that transitions a Jira issue to a new status from a macOS
Terminal (compatible with the Bash 3.2 that ships with macOS, and with newer
Bash versions on Linux).

### Prerequisites

- `curl` (preinstalled on macOS)
- `jq` — install on macOS with Homebrew: `brew install jq`

### Usage

```sh
./update_jira_status.sh --ticket <ISSUE-KEY> --status <STATUS> --token <TOKEN> --url <BASE-URL>
```

| Argument | Description |
| --- | --- |
| `--ticket` | Jira issue key, e.g. `KAN-4`. |
| `--status` | Destination status name, exactly as it appears in Jira. Quote multi-word statuses, e.g. `--status "In Progress"`. Status names are case-sensitive. |
| `--token` | API token, sent as `Authorization: Bearer <token>`. |
| `--url` | Base URL of your Jira instance, e.g. `https://jira.example.com`. |
| `-h`, `--help` | Print the argument format and an example, then exit. |

### Example

```sh
chmod +x update_jira_status.sh   # first time only
./update_jira_status.sh --ticket KAN-4 --status "In Progress" \
    --token "$JIRA_TOKEN" --url https://jira.example.com
```

The script first fetches the transitions currently available for the issue
(`GET /rest/api/2/issue/<ticket>/transitions`), picks the transition whose
destination status matches `--status` exactly, and then executes it
(`POST` to the same endpoint). If no available transition leads to the
requested status, the script lists the destination statuses that are
currently reachable, changes nothing, and exits nonzero.

### Authentication

The token is sent as a bearer token (`Authorization: Bearer <token>`), which
works with personal access tokens on Jira Server / Data Center. Jira Cloud
API tokens normally require basic authentication with your account email
(`email:token`), which this script does not implement; a Cloud deployment may
need a different auth flow.

### Security notes

- The script never prints the token in its output or diagnostics.
- Passing secrets on the command line exposes them to your shell history and
  to other local processes (e.g. `ps`). Prefer storing the token in an
  environment variable and passing `--token "$JIRA_TOKEN"`, as in the example
  above.
