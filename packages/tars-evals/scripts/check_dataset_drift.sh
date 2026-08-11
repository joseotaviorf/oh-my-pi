#!/usr/bin/env bash
# Local mirror of the `check-dataset-drift` step in .woodpecker/tars_evals.yml.
#
# Regenerates the in-scope datasets and fails if the committed YAML differs,
# catching an edited golden query whose dataset was never regenerated and an
# orphaned dataset whose source doc was deleted.
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

# Mirrors CI: `git diff` alone misses a brand-new dataset file generated for
# a newly-added metric_entities doc — it has no committed version to diff
# against, so it silently stays untracked instead of failing this check.
UNTRACKED="$(git ls-files --others --exclude-standard -- "$PKG_ROOT/datasets/" || true)"
if ! git diff --exit-code -- "$PKG_ROOT/datasets/" || [[ -n "$UNTRACKED" ]]; then
    {
        echo ""
        echo "ERROR: datasets/ is out of sync with docs/llm_context."
        echo "Regenerating in-scope stems changed the committed YAML above."
        if [[ -n "$UNTRACKED" ]]; then
            echo "Untracked generated dataset(s) must be committed:"
            printf '%s\n' "$UNTRACKED"
        fi
        echo "Review it and commit:"
        echo "    git add packages/tars-evals/datasets/"
        echo ""
        echo "(Locally this also fires on dataset edits you have not committed"
        echo " yet — CI runs against a clean tree.)"
    } >&2
    exit 1
fi
echo "datasets/ is in sync with the changed context docs."
