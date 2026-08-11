#!/usr/bin/env bash
# Source this to load the tars LiteLLM key into your CURRENT shell from Vault:
#   source scripts/setup_credentials.sh
#
# Use this for ad-hoc `uv run inspect eval ...` / `inspect view` runs and for
# the Inspect AI VS Code extension (which inherits your shell env). The
# `make eval-suite` target fetches the key on its own and does NOT require
# this to be sourced first.
#
# The secret is read on demand from Vault via qli — it is never written to .env
# or committed. Mirrors quintoml agentic-chatbot-service/scripts/setup_credentials.sh.

_tars_evals_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

if _key="$("$_tars_evals_dir/scripts/fetch_litellm_key.sh")"; then
    export OPENAI_API_KEY="$_key"
    export LITELLM_API_KEY="$_key"
    echo "Exported OPENAI_API_KEY + LITELLM_API_KEY from Vault (apps/forno/litellm/zordon-tars-llm). No secret written to disk."
else
    echo "Failed to fetch LiteLLM key from Vault — see error above." >&2
fi

unset _key _tars_evals_dir
