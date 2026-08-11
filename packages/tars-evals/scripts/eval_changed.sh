#!/usr/bin/env bash
# Local mirror of the `tars-evals-changed` gate step in
# .woodpecker/tars_evals.yml: evaluate only the stems the diff affects.
#
# Reads .tars-eval-stems. Prefer `make eval-changed`, which resolves the
# scope and drift-checks first, exactly as the pipeline does.
#
#   DRY_RUN=1 make eval-changed   # list what would run, spend nothing
#
# Exit codes are the queue's (README "Exit codes — what actually gates CI"):
# 1 = the SQL-quality gate legitimately failed, 2 = the harness itself broke.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PKG_ROOT"

STEMS_FILE="${TARS_EVAL_STEMS_FILE:-$PKG_ROOT/.tars-eval-stems}"

# Load-bearing rather than an optimization: run_dataset_queue.sh with no stem
# arguments evaluates EVERY dataset, so an empty list must short-circuit here
# instead of falling through to the queue.
if [[ ! -s "$STEMS_FILE" ]]; then
    echo "No changed dataset stems — nothing to evaluate."
    exit 0
fi

stems=()
while IFS= read -r stem || [[ -n "$stem" ]]; do
    [[ -z "$stem" ]] && continue
    stems+=("$stem")
done <"$STEMS_FILE"

echo "Stems to evaluate: ${stems[*]}"

set +e
scripts/run_dataset_queue.sh "${stems[@]}"
rc=$?
set -e

# Always surface the per-stem reports — a bare exit code is not enough to
# debug a judge disagreement.
for report in logs/per_dataset/*/gate_report.txt; do
    [[ -f "$report" ]] || continue
    echo ""
    echo "----- $report -----"
    cat "$report"
done
exit "$rc"
