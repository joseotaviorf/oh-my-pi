# tars-evals

Inspect AI harness that evaluates the `tars` skill against golden business
questions. Golden-query datasets live in `datasets/*.yaml`. Most files are
`# auto-generated` from `docs/llm_context/metric_entities/*.md`; hand-authored
datasets (no `# auto-generated` header) are never overwritten on regen.

See the core harness README in the stacked PR for install, credentials, and
runtime layout. This PR adds dataset generation from context docs.

## Generating datasets from context docs

`make generate-datasets` materializes golden queries from metric entity docs
into `datasets/{stem}.yaml` (one file per metric entity). Business-entity docs
are not scanned.

```bash
make generate-datasets
# preview only (no filesystem writes):
uv run python scripts/generate_datasets_from_context_docs.py --dry-run
```

### Scoped generation

By default the generator scans every metric doc, which aborts on the first
hand-authored dataset it would have to overwrite. Scoping restricts both
generation and pruning to a set of stems:

```bash
make generate-datasets STEMS="ongoing_listings supply_retention_sale"
make generate-datasets STEMS_FILE=.tars-eval-expected-stems
```

`--stems-file` takes one stem per line (blank lines and `#` comments ignored).
An empty stems file is a valid no-op that exits `0`.

`--skip-hand-authored` downgrades an in-scope hand-authored collision from exit
`1` to a logged skip (used by CI drift checks in a follow-up PR).

## Running evals and gate orchestration

Per-dataset evals run in parallel via a stem queue, then rollup and gate check:

```bash
make eval-suite              # all datasets
make eval-suite STEM=turnover
make eval-rollup
make eval-check-gate
```

`changed_dataset_stems.py` resolves which dataset stems a git diff affects
(eval stems vs scope stems for drift/regen). See orchestration tests for the
Woodpecker pairing contract.

## Local CI parity

These Makefile targets mirror `.woodpecker/tars_evals.yml` so you can run the
same scope/drift/eval flow locally before pushing:

```bash
make eval-scope
make drift-check
make eval-changed
# DRY_RUN=1 make eval-changed   # scope + drift only, no LLM eval
```

Override the diff range with `BASE=` / `HEAD=` (default: merge base with
`origin/master`).

## Quick start

```bash
cd packages/tars-evals
make install
make test
make lint
```
