#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

uv sync --group dev
uv run streamlit run app.py \
    --server.headless true \
    --server.address 127.0.0.1
