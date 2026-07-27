#!/usr/bin/env bash
# Thin wrapper: eval "$(astro/scripts/export_qli_vault_token.sh)"
# Implementation: export_qli_vault_token.py
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/export_qli_vault_token.py" "$@"
