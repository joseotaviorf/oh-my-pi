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

### New metric docs without datasets (CI)

Adding a metric entity doc without committing the matching
`datasets/{stem}.yaml` **does not block the PR**. CI prints a **warning** and
merges are allowed so context contributions are not gated on eval setup.

Follow up when ready:

```bash
make generate-datasets STEMS=condo_refund
git add datasets/condo_refund.yaml
```

Once the dataset is committed, later edits to that doc run the normal blocking
drift check and TARS eval gate. Existing datasets with committed YAML still
fail CI when golden queries change without regenerating.

Which evals a domain-doc edit triggers is decided in one direction only: metric
docs declare their dependencies in ``## Related Domain Entities`` and CI inverts
that into a reverse index. A domain doc nothing points at resolves to zero stems
and merges silently — with far more domain docs than metric docs, having no
linked metric is the normal state, not an anomaly. CI never fail-closes to every
dataset stem.

Lookup uses the domain doc's H1 title, since that is the name metric docs cite,
and falls back to the filename. A metric doc citing a domain entity that no doc
answers to is a typo, and CI warns about it on the PR that introduces it.

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

## Exit codes — what actually gates CI

`build_rollup.py` is the one authoritative gate; the queue and
`eval_changed.sh` propagate its code unchanged.

| Code | Meaning | What to do |
|------|---------|------------|
| 0 | The suite cleared `gate_pass_rate`. | Nothing. |
| 1 | **SQL quality regressed.** Samples were graded and too few passed. | Read the failing samples in `gate_report.txt` and fix the context docs or the skill. |
| 2 | **The harness or its infrastructure broke.** A malformed/missing summary, or an *inconclusive* run. | Rerun. Do not read it as a quality signal. |

**In CI the eval gate is advisory.** `.woodpecker/tars_evals.yml` marks the
`tars-evals-changed` step `failure: ignore`, so neither exit code blocks a PR
or a deployment — the step goes red, prints a banner naming which failure mode
it hit, and the pipeline carries on. An LLM judge grading generated SQL is not
a deterministic check, and this suite has measurable run-to-run variance, so a
red gate is evidence to read rather than a wall to climb.

The deterministic steps around it still block, because each has a single
correct answer: `resolve-eval-scope`, `check-dataset-drift` (an edited golden
query whose dataset was never regenerated) and `unit-tests-tars-evals`.

Locally nothing is suppressed — `make eval-suite` and `make eval-changed`
return the real exit code.

A run is **INCONCLUSIVE** when the share of samples that never produced a
verdict (connection failures, judge parse errors) exceeds `max_error_rate` in
`config.yaml`. This exists because an outage otherwise looks exactly like a
regression: on 2026-08-17 the LiteLLM ingress dropped mid-run, 58 of 77 samples
died in the TLS handshake, and the gate reported "13% passed" as though the SQL
had gotten worse. Errors below the ceiling still count against the pass rate, so
flakiness is never free.

Model calls retry with bounded exponential backoff before a sample is written
off — see `src/tars_evals/retry.py`:

```bash
TARS_EVAL_MAX_RETRIES=6        # HTTP retries per model request (0 = fail fast)
TARS_EVAL_REQUEST_TIMEOUT=300  # ceiling per request INCLUDING its retries; 0 = none
TARS_EVAL_RETRY_ON_ERROR=0     # whole-sample retries — replays the full ReAct loop
```

Concurrency knobs, if the proxy pushes back (aggregate connections ≈ workers ×
per-stem connections):

```bash
TARS_EVAL_WORKERS=2            # concurrent per-stem processes
TARS_EVAL_MAX_CONNECTIONS=4    # caps per-stem sample concurrency (default: stem size)
```

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

## Inspect log archival (S3)

Woodpecker's `tars-evals-changed` step best-effort uploads per-stem Inspect
logs to `s3://5a-tars-prod-data/evals/inspect/…` via
`scripts/upload_inspect_logs_s3.py`. Upload failures do not mask a gate result
unless `TARS_EVAL_REQUIRE_S3_UPLOAD=1`.

```bash
uv run --with boto3 python scripts/upload_inspect_logs_s3.py \
  --source logs/per_dataset \
  --extra gate_summary.json
```

### Viewing archived logs locally

`scripts/view_inspect_logs_s3.py` starts Inspect View against the S3 archive
directly (no `aws s3 sync`). It authenticates with **QLI → ConsoleMe**, applies
temporary credentials only for the duration of the in-process viewer, and binds
to **http://127.0.0.1:7575**.

Prerequisites:

1. [QLI](https://github.com/quintoandar/qli) installed and logged in (`qli login`).
2. A ConsoleMe role that can read `s3://5a-tars-prod-data/evals/inspect/` —
   pick one via [ConsoleMe](https://consoleme.sre.quintoandar.com.br/) /
   `qli aws list --arn-only`.

```bash
# Discover what was actually uploaded (archive root → year → day → pr → pipeline):
make inspect-view-s3 LIST=1
make inspect-view-s3 LIST=1 S3_URI=s3://5a-tars-prod-data/evals/inspect/2026/08/07

# Open a concrete CI run (example that exists in the archive):
make inspect-view-s3 \
  S3_URI=s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-26512/pipeline-89418

# Pin the role (skips interactive QLI role selection):
make inspect-view-s3 \
  ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/YOUR_ROLE \
  S3_URI=s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-26512/pipeline-89418
```

Equivalent without Make:

```bash
uv run python scripts/view_inspect_logs_s3.py --list
uv run python scripts/view_inspect_logs_s3.py \
  --log-dir s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-26512/pipeline-89418 \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/YOUR_ROLE
```

Then open **http://127.0.0.1:7575** in your browser (CTRL+C stops the server).

**Legacy / ambient credentials:** if you already exported temporary credentials
in the shell (Weep `weep export …` or a prior `eval "$(qli aws export …)"`),
skip the launcher's QLI step:

```bash
make inspect-view-s3 USE_AMBIENT=1 S3_URI=s3://5a-tars-prod-data/evals/inspect/...
# or:
uv run python scripts/view_inspect_logs_s3.py --use-ambient-credentials \
  --log-dir s3://5a-tars-prod-data/evals/inspect/...
```

Environment overrides: `TARS_EVAL_S3_URI`, `TARS_EVAL_S3_BUCKET`,
`TARS_EVAL_S3_PREFIX_ROOT`, `TARS_EVAL_S3_ROLE_ARN`,
`TARS_EVAL_INSPECT_VIEW_PORT`.

## Quick start

```bash
cd packages/tars-evals
make install
make test
make lint
```
