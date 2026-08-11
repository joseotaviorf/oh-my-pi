#!/usr/bin/env bash
# Print the tars LiteLLM proxy key to stdout, fetched from Vault via qli.
#
# The key is NEVER stored in .env or committed — it is read on demand from
# Vault (apps/forno/litellm/zordon-tars-llm#key), the same secret CI pulls via
# the Woodpecker vault plugin (apps/shared/litellm/zordon-tars-llm#key in
# .woodpecker/*). This mirrors quintoml agentic-chatbot-service's
# scripts/setup_credentials.sh (`qli kv get ... | sed 's/^key: //'`).
#
# Auth is handled by qli itself (keycloak SSO); run `qli kv get <path>` once
# interactively if you are not yet logged in. Override the path for a
# different env/key with TARS_LITELLM_VAULT_PATH.

set -euo pipefail

VAULT_PATH="${TARS_LITELLM_VAULT_PATH:-apps/forno/litellm/zordon-tars-llm}"

if ! command -v qli >/dev/null 2>&1; then
    echo "ERROR: qli not found on PATH. Install the QuintoAndar CLI (qli) to fetch the LiteLLM key from Vault." >&2
    exit 1
fi

# `qli kv get` prints "key: <value>"; strip the field prefix to get the raw value.
key="$(qli kv get "$VAULT_PATH" --no-prompt 2>/dev/null | sed -n 's/^key:[[:space:]]*//p')"

if [[ -z "$key" ]]; then
    echo "ERROR: could not read a 'key' field from Vault at '$VAULT_PATH'." >&2
    echo "       Are you logged in to qli? Try running: qli kv get $VAULT_PATH" >&2
    exit 1
fi

printf '%s' "$key"
