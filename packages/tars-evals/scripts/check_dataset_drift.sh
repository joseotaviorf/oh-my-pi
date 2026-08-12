#!/usr/bin/env bash
# Local mirror of the `check-dataset-drift` step in .woodpecker/tars_evals.yml.
#
# Regenerates the in-scope datasets and validates drift against committed YAML.
#
# Blocking failures (exit 1):
#   - tracked datasets/ differ from regeneration (stale golden queries, prune
#     after doc deletion, rename cleanup, etc.)
#
# Non-blocking warnings (exit 0):
#   - untracked generated YAML for stems that have no committed dataset yet
#     (new metric entity docs). Lets doc-only PRs merge while eval coverage is
#     added in a follow-up.
#
# Reads .tars-eval-expected-stems. Prefer `make drift-check`, which resolves
# the scope first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PKG_ROOT"

SCOPE_FILE="${TARS_EVAL_SCOPE_FILE:-$PKG_ROOT/.tars-eval-expected-stems}"

if [[ ! -s "$SCOPE_FILE" ]]; then
    echo "No in-scope dataset stems — nothing to drift-check."
    exit 0
fi

# Scoped on purpose: an unscoped run refuses to overwrite every hand-authored
# dataset in the tree and would fail on stems this diff never touched.
# --skip-hand-authored: a hand-authored dataset is never regenerated, so it
# cannot drift; without this, editing the source doc of one would fail here
# forever with no change available to the author that could fix it.
uv run python scripts/generate_datasets_from_context_docs.py \
    --stems-file "$SCOPE_FILE" \
    --skip-hand-authored

# Blocking: committed YAML out of sync (includes prune-after-delete and renames).
if ! git diff --exit-code -- "$PKG_ROOT/datasets/"; then
    {
        echo ""
        echo "ERROR: datasets/ is out of sync with docs/llm_context."
        echo "Regenerating in-scope stems changed committed YAML above."
        echo "Reproduce and fix locally, then commit the regenerated YAML:"
        echo "  cd packages/tars-evals && make drift-check"
        echo ""
        echo "(Locally this also fires on dataset edits you have not committed"
        echo " yet — CI runs against a clean tree.)"
    } >&2
    exit 1
fi

UNTRACKED="$(git ls-files --others --exclude-standard -- "$PKG_ROOT/datasets/" || true)"
if [[ -n "$UNTRACKED" ]]; then
    {
        echo ""
        echo "WARN: merge allowed — new context without committed eval dataset(s)."
        echo "Untracked generated dataset(s) (add in a follow-up PR for TARS eval):"
        printf '%s\n' "$UNTRACKED"
        echo ""
        echo "Generate and commit when ready:"
        echo "  cd packages/tars-evals && make generate-datasets STEMS=<stem>"
        echo ""
        echo "Eval coverage starts once the YAML lands; existing datasets still"
        echo "require strict drift sync when their source docs change."
    } >&2
    echo "datasets/ drift check passed with eval-coverage warning (uncommitted new datasets)."
    exit 0
fi

echo "datasets/ is in sync with the changed context docs."
