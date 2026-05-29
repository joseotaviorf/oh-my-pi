#!/usr/bin/env bash
# Bootstrap cluster migration scripts and instance-mapping fix into a worktree.
set -euo pipefail
MAIN_REPO="${MAIN_REPO:?MAIN_REPO must be set to the path of the bi-etl-ejuice repository}"
REPO_ROOT="$(pwd)"
cd "$REPO_ROOT"

VALIDATION_DIR="packages/bietlejuice-compiler/scripts/validation"
mkdir -p "$VALIDATION_DIR"
cp "$MAIN_REPO/$VALIDATION_DIR/cluster_migration_stack.sh" \
   "$MAIN_REPO/$VALIDATION_DIR/promote_cluster_validation_to_prod.py" \
   "$VALIDATION_DIR/"
chmod +x "$VALIDATION_DIR/cluster_migration_stack.sh"

MAPPING="packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/cluster_validation_mapping.py"
if [[ -f "$MAIN_REPO/$MAPPING" ]]; then
  mkdir -p "$(dirname "$MAPPING")"
  cp "$MAIN_REPO/$MAPPING" "$MAPPING"
fi

if [[ -f "$MAIN_REPO/Makefile" ]] && grep -q 'STRIP_DECLARATION=1' "$MAIN_REPO/Makefile"; then
  cp "$MAIN_REPO/Makefile" Makefile
fi

echo "Bootstrapped cluster migration tooling in $(pwd)"
