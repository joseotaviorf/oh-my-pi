# ADR 001 — Split CI/CD pipeline by file-change path filters

## Status

Accepted

## Context

bi-etl-ejuice is a monorepo that consolidates all batch data pipeline logic for
QuintoAndar. It hosts approximately 771 Airflow DAGs across 24 business domains.
A single pull-request push can touch any combination of the following artefact
types:

| Artefact type | Example paths |
|---|---|
| Python package source | `bietlejuice/**` |
| DAG YAML declarations | `dags/**/*_declaration.yml` |
| SQL query files | `dags/**/queries/**` |
| Governance metadata YAML | `dags/**/metadata/**` |
| Data-quality assertions | `dags/**/data_quality/**` |
| Core model JSON schemas | `dags/**/schemas/**` |
| Custom Spark jobs | `dags/**/spark_jobs/**` |
| Shell init and wonka scripts | `scripts/init_script.sh`, `scripts/wonka/**` |
| Qube semantic layer modules | `bietlejuice/qube/**` |

Before this decision, the CI/CD pipeline ran as a single monolithic pipeline.
Every push — including changes that only touched SQL or metadata YAML — triggered
Python linting, unit tests, integration tests, and all validation steps. This led
to:

- **Slow feedback**: engineers waited for unrelated checks to complete (e.g.,
  running PySpark integration tests for a metadata-only change).
- **Wasted compute**: CI runners executed steps that could not possibly fail
  given the files that changed.
- **Noisy status reporting**: all pipeline steps appeared in every PR regardless
  of relevance.

At the same time, the release (deployment) steps must run conditionally per
artefact type: uploading Databricks SQL queries when only queries changed should
not also re-package and redeploy the Python wheel.

Woodpecker CI supports two mechanisms that together solve this problem:

1. **Pipeline-level `when.path` filters** — an entire pipeline file is skipped
   if none of the declared `include` globs match the changed files.
2. **Step-level `when.path` filters** — individual steps within a pipeline can
   additionally gate themselves on finer-grained path patterns.
3. **`on_empty: false`** — when a path filter matches zero files the pipeline
   (or step) is skipped rather than erroring.
4. **`depends_on: []`** — steps with no declared dependency run in parallel,
   reducing wall-clock time within a pipeline.

## Decision

Woodpecker CI is split into four separate pipeline files, each responsible for a
cohesive concern and each triggered only when its relevant files change.

```
.woodpecker/
├── lint.yml         # Python style checks and file-structure validation
├── tests.yml        # Unit, integration, and core-model tests
├── validations.yml  # DAG-specific structural and governance validations
└── release.yml      # Artefact builds, S3 uploads, and Astronomer deployment
```

### `lint.yml` — style and file-structure checks

- **Triggered when**: any `**/*.py` file changes (`on_empty: false`).
- **Steps**: `check-style-python` (Black + Flake8) and `files-validation-python`
  (Woodpecker pipeline YAML consistency tests). `check-style-python` declares
  `depends_on: []` and starts immediately; `files-validation-python` carries no
  `depends_on` annotation and therefore runs sequentially after it.
- **Rationale**: style issues are cheap to detect and should never block
  unrelated artefact deployments.

### `tests.yml` — automated test suite

- **Triggered when**: any `**/*.py` file changes (`on_empty: false`).
- **Steps**:
  - `unit-tests-python` — full pytest unit-test suite.
  - `integration-tests-python` — integration test suite.
  - `core-model-tests-and-coverage` — scoped additionally to
    `dags/core/**/*.py`, `tests/core_model_dags/**/*.py`, and
    `bietlejuice/base/core_models/**/*.py` via a nested step-level path filter.
  - Unit and integration tests run in parallel (`depends_on: []`).
- **Rationale**: test execution against a PySpark image is expensive; skipping
  it for SQL-only or metadata-only changes avoids significant unnecessary cost.

### `validations.yml` — DAG structural and governance validations

- **Triggered when**: path-filter-specific sub-sets of `dags/**` change. Each
  validation step carries its own `when.path` filter so only the relevant
  checks execute:

  | Step | Path filter | Branch filter |
  |---|---|---|
  | `validate-dag-declaration-files` | `dags/**/*_declaration.yml` (also `*.yaml`) | _(all branches)_ |
  | `validate-dags-up-to-standard` | `dags/**` | _(all branches)_ |
  | `validate-dags-dependencies-forno` | `dags/**` | exclude `master`, `hotfix/*` |
  | `validate-dags-dependencies-prod` | `dags/**` | `master`, `hotfix/*` only |
  | `validate-dependency-file-correctness` | `dags/**` | _(all branches)_ |
  | `validate-metadata-files-content` | `dags/**/metadata/**` | exclude `forno`, `hotfix/*` |
  | `validate-metadata-files-exist` | `dags/**/metadata/**` | exclude `forno`, `hotfix/*` |
  | `validate-lineage-consistency` | `dags/**/metadata/**` | _(all branches)_ |
  | `validate-core-model-schemas` | `dags/core/**/schemas/**` | _(all branches)_ |
  | `validate-core-model-schema-content` | `dags/core/**/schemas/**` | _(all branches)_ |
  | `validate-source-layer-policy` | _(no path filter)_ | exclude `forno`, `hotfix/*` |

- All steps run in parallel (`depends_on: []`).
- **Rationale**: governance and structural validations are fast (no Spark) but
  must be granular — re-running the metadata validator for a declaration-only
  change is wasteful.

### `release.yml` — artefact build and deployment

- **Depends on**: `lint`, `tests`, and `validations` pipelines (Woodpecker
  `depends_on` at the pipeline level).
- **Triggered when**: per-artefact path filters match. Each upload or deploy
  step carries its own `when.path` filter:

  | Step group | Path filter |
  |---|---|
  | Python wheel build and S3 upload | `bietlejuice/**` |
  | `init_script.sh`, `emr_init_script.sh`, and wonka shell assets | `scripts/init_script.sh`, `scripts/emr_init_script.sh`, `scripts/wonka/**` |
  | Wonka DAG shell scripts | `dags/wonka/**` |
  | `bietlejuice` module + DAG package S3 sync and Astronomer deploy | `dags/**` |
  | Databricks SQL queries | `dags/**/queries/**` |
  | Databricks Spark jobs | `dags/**/spark_jobs/**` |
  | Data-quality YAML | `dags/**/data_quality/**` |
  | Core model JSON schemas | `dags/**/schemas/**` |
  | Governance metadata (propagator + DataHub) | `dags/**/metadata/**` |
  | Qube semantic-layer modules | `bietlejuice/qube/**` |

- The git clone uses `depth: 2` and `partial: false` so that `git diff HEAD~1 HEAD`
  is available if needed (the same settings are shared with `tests.yml` and
  `validations.yml`). The `create-dag-files-from-git-diff` step is currently
  commented out; the Astronomer deployment flow now works by syncing the full
  `bietlejuice` package and the `dags/` directory to S3 via `beethoven-s3-sync`,
  followed by an `astronomer-deploy-dags` step that depends on both syncs.
- Steps upload to the correct environment bucket (`forno` or `prod`) based on
  the branch (`forno`, `master`, or `hotfix/*`).
- **Rationale**: deploying only the artefacts that changed prevents unnecessary
  S3 writes, Astronomer deployments, and the risk of deploying a stale wheel
  alongside a metadata-only change.

### Parallelism model

```
lint ──────────────────────────────────────────────────────────────────┐
  ├─ check-style-python (depends_on: [] — starts immediately)          │
  └─ files-validation-python (sequential after check-style-python)     │
                                                                       ▼
tests ─────────────────────────────────────────────────────────► release
  ├─ unit-tests-python (parallel)                                      ▲
  └─ integration-tests-python (parallel)                               │
                                                                       │
validations ──────────────────────────────────────────────────────────┘
  ├─ validate-dag-declaration-files (parallel)
  ├─ validate-metadata-files-content (parallel)
  └─ ... (all steps parallel)
```

## Consequences

### Positive

- **Faster feedback**: engineers receive results only for the checks relevant to
  their changes, often in under two minutes for metadata or SQL-only PRs.
- **Lower CI cost**: PySpark and packaging steps are not executed when only YAML
  or SQL files change.
- **Separation of concerns**: lint, test, validation, and deployment are clearly
  delineated pipeline responsibilities; failures are easier to attribute and fix.
- **Selective deployment**: only artefacts whose source files changed are
  uploaded to S3, reducing the risk of inadvertent side-effects (e.g., rewriting
  a production S3 prefix that has not changed).
- **Intra-pipeline parallelism**: steps with no dependencies run concurrently,
  minimising wall-clock time within each pipeline.

### Negative / risks

- **Path-filter drift**: if a new artefact directory is added (e.g., a new DAG
  sub-folder type) and the corresponding `when.path` filter is not added to
  `release.yml`, the upload step will silently never run. Engineers must keep
  path filters and folder conventions in sync.
- **Release dependency chain on skipped pipelines**: `release.yml` declares
  `depends_on: [lint, tests, validations]`. When a pipeline is skipped because
  no matching files changed (e.g., a metadata-only push skips `lint` and
  `tests`), Woodpecker treats the skipped pipeline as successful. This is the
  intended behaviour but must be understood by engineers troubleshooting a
  pipeline that appears to have been skipped.
- **`validate-source-layer-policy` skips forno and hotfix branches**: this step
  lacks a path filter and runs on every push, but carries a
  `branch: exclude: [forno, hotfix/*]` guard. It is skipped on forno staging
  runs and hotfix branches. Engineers working hotfixes should validate locally
  with `make validate-source-layer-policy` before merging to master.
- **`depth: 2` clone assumption**: `release.yml`, `tests.yml`, and
  `validations.yml` all clone with `depth: 2` and `partial: false` so that
  `git diff HEAD~1 HEAD` is available if needed. The
  `create-dag-files-from-git-diff` step that originally motivated this setting
  is currently commented out. The shallow clone assumption — at most one commit
  per push (standard squash-merge workflow) — remains, and force-pushes or
  multi-commit pushes may cause diffs to miss changes.
