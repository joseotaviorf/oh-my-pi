#!/usr/bin/env bash
# Local mirror of the `resolve-eval-scope` step in .woodpecker/tars_evals.yml.
#
# Writes the two stem lists the rest of the local gate reads:
#   .tars-eval-stems           what to evaluate
#   .tars-eval-expected-stems  what to drift-check (includes deleted docs)
#
# Prefer `make eval-scope`, which passes BASE/HEAD through for you.
#
# Diff range: $TARS_EVAL_BASE/$TARS_EVAL_HEAD when set, otherwise this
# branch's merge base with origin/master — the same range the PR gate diffs,
# since `git diff A...B` == `git diff $(git merge-base A B) B`. When
# origin/master can't be resolved (no remote, fresh clone), no --base is
# passed and changed_dataset_stems.py falls back to its own auto-detection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PKG_ROOT"

STEMS_FILE="${TARS_EVAL_STEMS_FILE:-$PKG_ROOT/.tars-eval-stems}"
SCOPE_FILE="${TARS_EVAL_SCOPE_FILE:-$PKG_ROOT/.tars-eval-expected-stems}"

base="${TARS_EVAL_BASE:-}"
if [[ -z "$base" ]]; then
    base="$(git merge-base origin/master HEAD 2>/dev/null || true)"
fi

args=()
[[ -n "$base" ]] && args+=(--base "$base")
[[ -n "${TARS_EVAL_HEAD:-}" ]] && args+=(--head "$TARS_EVAL_HEAD")

# stdout is the machine-readable stem list; the human-readable summary below
# is this script's actual output. WARN/NOTE lines stay on stderr either way.
uv run python scripts/changed_dataset_stems.py \
    "${args[@]+"${args[@]}"}" \
    --write-eval-stems "$STEMS_FILE" \
    --write-scope-stems "$SCOPE_FILE" >/dev/null

echo "diff base   : ${base:-<auto-detected>}"
echo "eval stems  (run through the harness): $(tr '\n' ' ' <"$STEMS_FILE")"
echo "scope stems (drift-checked)          : $(tr '\n' ' ' <"$SCOPE_FILE")"

# A committed-diff resolver cannot see the working tree, so someone who edits
# a doc and immediately runs the gate would get a silently empty scope.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$repo_root" ]] &&
    ! git diff --quiet HEAD -- "$repo_root/docs/llm_context" 2>/dev/null; then
    echo "NOTE: uncommitted changes under docs/llm_context are not in scope" \
        "until you commit them." >&2
fi
