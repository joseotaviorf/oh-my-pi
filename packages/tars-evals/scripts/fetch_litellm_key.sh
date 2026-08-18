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
# Passed to qli as -e. Without it, qli falls back to whatever `qli env set`
# last selected globally — so this script hard-coded the apps/forno/… path but
# let an unrelated ambient setting decide which Vault SERVER to ask (forno is
# vault-sandbox.…, prod is vault.…). Anyone whose env happened to be on prod
# got a bare 403 "permission denied" that reads like an expired login.
# Override together with TARS_LITELLM_VAULT_PATH when pointing at another env.
VAULT_ENV="${TARS_LITELLM_VAULT_ENV:-forno}"

if ! command -v qli >/dev/null 2>&1; then
    echo "ERROR: qli not found on PATH. Install the QuintoAndar CLI (qli) to fetch the LiteLLM key from Vault." >&2
    exit 1
fi

# qli's stderr is captured to a file rather than merged into stdout: stdout
# holds the secret, so it must never be echoed back on the error path.
#
# Capturing the exit status explicitly is load-bearing. The previous form,
#   key="$(qli kv get ... 2>/dev/null | sed -n '...')"
# combined `set -e`, `pipefail` and a discarded stderr, so an expired SSO
# session killed this script *before* the diagnostic below could print — and
# the caller (run_dataset_queue.sh) died the same way. A whole eval run
# aborting with no output and exit 1 is not a debuggable failure.
qli_stderr="$(mktemp)"
trap 'rm -f "$qli_stderr"' EXIT

if ! qli_stdout="$(qli kv get "$VAULT_PATH" -e "$VAULT_ENV" --no-prompt 2>"$qli_stderr")"; then
    echo "ERROR: 'qli kv get $VAULT_PATH -e $VAULT_ENV' failed. qli said:" >&2
    sed 's/^/       /' "$qli_stderr" >&2
    echo "       A 403 here means your login has no access to that path in the" >&2
    echo "       '$VAULT_ENV' Vault; run 'qli login' if the session has expired." >&2
    exit 1
fi

# `qli kv get` prints "key: <value>"; strip the field prefix to get the raw value.
key="$(printf '%s\n' "$qli_stdout" | sed -n 's/^key:[[:space:]]*//p')"

if [[ -z "$key" ]]; then
    echo "ERROR: no 'key' field in the Vault secret at '$VAULT_PATH'." >&2
    echo "       Check the path: qli kv get $VAULT_PATH" >&2
    exit 1
fi

printf '%s' "$key"
