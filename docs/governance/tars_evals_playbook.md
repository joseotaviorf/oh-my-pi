# TARS evals — developer playbook

How to add/edit golden queries, run the eval suite locally, and read what CI reports
when the `tars_evals` pipeline goes red.

Full reference (dataset generation flags, S3 log viewer, retry/concurrency knobs):
[`packages/tars-evals/README.md`](../../packages/tars-evals/README.md). This page is the
short path for the common cases.

## What this actually is

An [Inspect AI](https://inspect.aisi.org.uk/) harness that runs the real `tars` skill
against golden business questions and has an LLM judge (1–5, pass at 4) grade whether the
SQL it generates is *result-equivalent* to a hand-approved `expected_query`. It is a
quality signal about the `tars`/`unstable-srat` skill and the `docs/llm_context/` context
docs it reads — not a data-quality or dbt-style test.

**The eval gate is currently advisory, not blocking.** A red `tars-evals-changed` step in
CI does **not** stop your PR from merging. It exists so a regression is visible and
reviewable, not so it gates the pipeline — LLM-judge grading has measurable run-to-run
variance (rerunning an unchanged suite has flipped results before), so treating it as a
hard blocker produced false-positive CI blocks. Read a red step; don't fight it to green.

Two CI checks around it **do** still block, because they're deterministic (see
[When CI blocks](#when-ci-blocks-and-what-to-do) below): `check-dataset-drift` and
`unit-tests-tars-evals`.

## When do these evals even run?

Only when a PR touches:

- `docs/llm_context/metric_entities/**/*.md` or `docs/llm_context/domain_entities/**/*.md`
- `packages/tars-evals/**`
- `.woodpecker/tars_evals.yml`

No touch to those paths → the whole `tars_evals.yml` pipeline is skipped. If you're not
editing a metric/domain entity doc or the harness itself, none of this applies to you.

## Adding or editing a golden query

Datasets under `packages/tars-evals/datasets/*.yaml` are (mostly) **generated** — don't
hand-edit them unless the file lacks the `# auto-generated` header.

1. Edit the `## Golden Queries` section of the relevant doc, e.g.
   `docs/llm_context/metric_entities/turnover.md` (template:
   `docs/llm_context/metric_entities/_TEMPLATE.md`). Rules that matter for the eval:
   - Trino SQL dialect only — no Spark-only syntax (`QUALIFY`, `GROUP BY ALL`, `IFF`,
     3-arg `DATEDIFF`, `col:key` variant access).
   - No placeholders (`{var}`, `<VAR>`) — must be a runnable, standalone `SELECT`.
   - A bare CTE with no final `SELECT`, a query that references another query's CTE, or
     a "see query N above" stub gets silently dropped by the generator (with a stderr
     warning) — write each golden query as a complete, self-contained statement.
2. Regenerate the dataset:
   ```bash
   cd packages/tars-evals
   make generate-datasets STEMS=turnover
   ```
   (Omit `STEMS=` only if you're sure no hand-authored dataset will collide — the
   unscoped run aborts on the first one it would have to overwrite.)
3. Commit **both** the doc and the regenerated YAML together:
   ```bash
   git add docs/llm_context/metric_entities/turnover.md packages/tars-evals/datasets/turnover.yaml
   ```
   If you edit the doc's golden query and forget step 2, CI's `check-dataset-drift` step
   catches it and **blocks the PR**.

Editing a **hand-authored** dataset (no `# auto-generated` header — e.g. `turnover.yaml`,
`accounting.yaml`, `credit_metrics.yaml`, `er2rr.yaml`, `nps_fr.yaml`, …): edit the YAML
directly, it's never touched by the generator.

Brand-new metric doc with no dataset yet is fine to merge — CI only **warns**, it doesn't
block. Follow up whenever with the same `make generate-datasets STEMS=<stem>` + commit.

### Dataset shape, if you need to read one

```yaml
# auto-generated
# source: docs/llm_context/metric_entities/condo_refund.md
# Do not edit — regenerate with: make generate-datasets
items:
  - id: condo_refund-condo-refund-w-o-human-intervention-onboarding-okr
    question: '% Condo Refund w/o Human Intervention — Onboarding (OKR)'
    expected_query: "WITH heimdall AS (...) SELECT ..."
```
Only three fields matter: `id`, `question`, `expected_query`.

## Running it locally before you push

```bash
cd packages/tars-evals
make install              # uv sync (one-time / after deps change)
make eval-scope           # what would CI evaluate/drift-check, given your diff?
make drift-check          # would check-dataset-drift pass?
make eval-changed         # full local mirror of the CI gate (BASE=/HEAD= to override the diff range)
DRY_RUN=1 make eval-changed   # scope + drift only — no LLM calls, no cost
```

To run a specific stem end to end and read its report:

```bash
cd packages/tars-evals
export TARS_SKILL_DIR=/path/to/local/ai-tools/marketplace/tars/skills/tars
source scripts/setup_credentials.sh   # pulls the LiteLLM key from Vault via qli
make eval-suite STEM=turnover
cat logs/per_dataset/turnover/gate_report.txt
```

`make creds` checks the Vault key is reachable before you burn time on a run that will
fail at the credentials step.

## When CI blocks (and what to do)

| Step | Blocks the PR? | What it means |
|---|---|---|
| `resolve-eval-scope` | Yes | Failed to compute the diff scope — usually a git/parse bug, rare. |
| `check-dataset-drift` | **Yes** | You edited a golden query doc without regenerating its dataset (or deleted a doc but left an orphaned dataset). Run `make generate-datasets STEMS=<stem>` and commit the YAML. |
| `unit-tests-tars-evals` | **Yes** | The harness's own unit tests or lint failed. Fix like any other test failure: `cd packages/tars-evals && make test && make lint`. |
| `tars-evals-changed` | No (advisory) | The judge graded the generated SQL and either it regressed, or the run was inconclusive. See below. |

For the advisory step, CI prints a banner telling you which of two things happened:

- **"SQL QUALITY (advisory)"** — samples were graded and too few passed. Read the
  per-stem `gate_report.txt` printed in the step log (format below); it names the failing
  question and the judge's reasoning. Usually means the context doc's golden query and the
  skill's actual behavior have drifted apart — fix whichever is wrong.
- **"PRODUCED NO RESULT (advisory)"** — the harness or LiteLLM broke mid-run (exit code
  2), not a quality signal. Rerun the step. If it repeats, check the LiteLLM proxy.

Sample report format:

```
tars-evals gate  |  ai-tools main @ <sha>  |  epochs=1  score>=4  pass>90%

DATASET    SAMPLE                              SCORE  RESULT
turnover   turnover-global-2025-year-turnover    3/5   FAIL

GATE: 8/9 passed (88.9%) <= 90.0%  ->  FAIL

Failures:
- turnover / turnover-global-2025-year-turnover (3/5)
    <judge reasoning...>
```

To see the full agent transcript behind a CI run's judgment (not just the verdict),
view the archived Inspect logs (needs `qli login` + an S3-reading role — see the
[README](../../packages/tars-evals/README.md#viewing-archived-logs-locally) for role
lookup):

```bash
make inspect-view-s3 S3_URI=s3://5a-tars-prod-data/evals/inspect/<date>/pr-<N>/pipeline-<N>
```
Opens `http://127.0.0.1:7575`.

## FAQ

**Do I need to touch this at all?** Only if your PR edits
`docs/llm_context/{metric,domain}_entities/**` or `packages/tars-evals/**`. Everything
else in the repo is unaffected.

**A red `tars-evals-changed` step is blocking my merge button.** It shouldn't be — that
step is `failure: ignore`. If something appears to be genuinely blocking, it's one of
`resolve-eval-scope`, `check-dataset-drift`, or `unit-tests-tars-evals` — check which step
is actually red.

**I don't have Vault/qli access to run evals locally.** You can still validate everything
except the actual LLM judging: `make eval-scope`, `make drift-check`, and
`DRY_RUN=1 make eval-changed` need no credentials.
