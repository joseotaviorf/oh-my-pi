#!/usr/bin/env bash
# Release helper: resolve which DAG packages need processing via the same git diff as CI.
# Orchestration may call this alongside S3 / Beethoven uploads; DAG name discovery must stay in sync
# with scripts/ci_cd/changed_dag_names_from_git.sh (single source of truth).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
bash "${SCRIPT_DIR}/changed_dag_names_from_git.sh"
