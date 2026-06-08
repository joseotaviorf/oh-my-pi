#!/bin/bash
# Parse JIRA_OPS_CREDENTIALS_JSON (Vault kv#value) into flat exports for sync.
# Appends to vault-credentials. Never prints secret values.

set -euo pipefail

OUTPUT_FILE="${VAULT_CREDENTIALS_FILE:-./vault-credentials}"

if [[ -f ./vault-credentials ]]; then
    # shellcheck disable=SC1091
    set -a
    source ./vault-credentials
    set +a
fi

if [[ -z "${JIRA_OPS_CREDENTIALS_JSON:-}" ]]; then
    if [[ -n "${JIRA_OPS_USERNAME:-}" && -n "${JIRA_OPS_TOKEN:-}" && -n "${JIRA_OPS_CLOUD_ID:-}" ]]; then
        echo "Jira Ops credentials already exported as flat env vars"
        exit 0
    fi
    echo "ERROR: JIRA_OPS_CREDENTIALS_JSON is not set. Source vault-credentials first." >&2
    exit 1
fi

python3 - <<'PY' >>"$OUTPUT_FILE"
import json
import os
import shlex
import sys

raw = os.environ.get("JIRA_OPS_CREDENTIALS_JSON", "")
try:
    credentials = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"ERROR: JIRA_OPS_CREDENTIALS_JSON is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(credentials, dict):
    print("ERROR: JIRA_OPS_CREDENTIALS_JSON must decode to a JSON object", file=sys.stderr)
    sys.exit(1)

required = ("username", "token", "cloud_id")
missing = [key for key in required if not credentials.get(key)]
if missing:
    print(
        "ERROR: JSON credentials missing required keys: "
        + ", ".join(missing)
        + f". Present keys: {', '.join(sorted(credentials))}",
        file=sys.stderr,
    )
    sys.exit(1)

for env_name, key in (
    ("JIRA_OPS_USERNAME", "username"),
    ("JIRA_OPS_TOKEN", "token"),
    ("JIRA_OPS_CLOUD_ID", "cloud_id"),
):
    print(f"export {env_name}={shlex.quote(str(credentials[key]))}")
PY

echo "Exported JIRA_OPS_USERNAME, JIRA_OPS_TOKEN, JIRA_OPS_CLOUD_ID to $OUTPUT_FILE"
