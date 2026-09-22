# bi-etl-ejuice — Agent Instructions

QuintoAndar's central data-engineering monorepo: 834 DAG Builder DAGs, 871 Airflow DAGs
total (37 legacy Python), Spark jobs, and the `bietlejuice` Python libraries. Analytical ETL
with Kimball dimensional modeling, orchestrated in Airflow, executed on Databricks.

**Stack:** Python · Apache Airflow · Databricks/Spark · PostgreSQL · Kimball dimensional
modeling · managed with **[uv](https://docs.astral.sh/uv/)** · Ruff · pytest.

This file is the canonical, tool-agnostic instruction set. **Cursor** reads it directly
(root `AGENTS.md`, applied to every conversation); **Claude Code** reads it through the
`@AGENTS.md` import in `CLAUDE.md`. It is deliberately small: always-on essentials plus an
index to the detailed rules. The layer-architecture / ConfigurationService / TARS / hard
constraints live once in `.cursor/rules/core_min.mdc` (see "Where detailed rules live").

## Environment & toolchain (uv)

The repo is managed with **uv**: workspace packages under `packages/` plus the standalone
`bietlejuice-runtime`. `make install` runs `uv sync`; everything runs through `uv run`.
There is **no** bare-interpreter virtualenv to activate.

**NEVER run bare `python3`, `pip install`, `python -m venv`, or pyenv.** Bare `python3`
does not see the project dependencies (`import yaml` and friends fail), and a hand-rolled
venv misses both the workspace deps and the shared uv cache. Use uv instead:

| Need | Command |
|---|---|
| Run repo code / a package module | `uv run python …` or `uv run --directory packages/<pkg> python …` |
| Run a package's tests | `uv run --directory packages/<pkg> pytest …` |
| Use a lib the repo already has (e.g. `yaml`) | `uv run python -c "import yaml; …"` |
| One-off lib the repo does NOT depend on | `uv run --no-project --with <pkgs> python -c "…"` |
| Multi-line throwaway script needing extra libs | PEP 723 header (`# /// script` … `# dependencies = [...]` … `# ///`) + `uv run --script <file>` |
| Deps missing / env broken | `make install` (or work in the devcontainer) |

The `--no-project` / `--script` forms never read the workspace lockfile and reuse the
global uv cache (`~/.cache/uv`, persisted in the devcontainer), so repeated runs don't
reinstall. **This is the sanctioned scratch space for ad-hoc exploration** — do not create
a curated sandbox project or add a workspace dependency group for it.

Exception: a skill that *intentionally* isolates a CLI tool may do so — but prefer
`uvx` / `uv run --with` over a hand-rolled venv.

## Repository layout (key files)

- **`dags/`** — pipelines by business domain + DAG name. A typical folder: `*_declaration.yml`
  (Airflow schedule/workflow; generates `*_dag.py`), `queries/<layer>/<table>.sql`,
  `metadata/<layer>/<table>.yml`, plus optional `data_quality/`, `spark_jobs/`, `schemas/`.
- **`packages/`** — six installable `bietlejuice` projects: `bietlejuice-core` (shared
  config/validation/utils), `bietlejuice-airflow` (DAG builder, Airflow integration),
  `bietlejuice-airflow-operators` (Databricks/EMR operators), `bietlejuice-airflow-plugins`
  (Airflow plugins), `bietlejuice-runtime` (Spark/Qube/UDFs, Databricks-side; standalone uv
  project with per-DBR venvs), `bietlejuice-compiler` (`create-dag-files`, validation scripts,
  SQL tooling). Five of these are uv workspace members; runtime is standalone.
- **`astro/`** — local + Astro "dev" Airflow project (same image as CI). Forno/prod still use
  `make create-dag-files` (stubs + gitignored parse-time manifests). Astro "dev" uses
  `make create-astro-dag-files` (domain + migration bundles; see `.woodpecker/development.yml`).
- **`Makefile`** — all dev/CI targets (`install`, `create-dag-files`, `create-astro-dag-files`,
  `run-local-environment`, `check-style`, `tests`, the `validate-*` governance checks, …).

## Modeling rules (Kimball)

- Explicit grain; clear dimension/fact separation; business-semantic metrics.
- Dimensions singular `dim_*`; facts plural `fact_*`; DW surrogate keys `sk_*`.
- **SCD Type 2:** define and validate `dt_valid_from`, `dt_valid_to`, `is_current`, and
  non-overlapping validity logic.
- Treat metadata and data-quality checks as part of the deliverable (not optional).

## Adding a new ingested table — mandatory file checklist

When you register a table in `*_declaration.yml` you **must** also create (or CI fails):

1. **`queries/<layer>/<table>.sql`** — the transformation SQL for that layer.
2. **`metadata/<layer>/<table>.yml`** — schema metadata with `database_name`, `table_name`,
   `domain`, `owner`, `description`, and per-column `description` + `lineage`.

Validate before opening the PR:
```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-exist
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
# Regenerate dependencies.yaml only when SQL/metadata changes create cross-DAG deps.
# Luigi Jr and platform migration_* validation DAGs are excluded automatically.
make dependencies-file && git add dags/dependencies.yaml
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-dependency-file-correctness
```

Metadata authoring guide: the **`create-metadata-files`** skill
(`.cursor/skills/create-metadata-files/SKILL.md`).

## Where detailed rules live (load on demand)

Cursor auto-loads `.cursor/rules/*.mdc` by path/glob and applies always-on ones automatically;
**Claude Code does not auto-read them** — open these explicitly when relevant:

- **`.cursor/rules/core_min.mdc`** — always-on essentials NOT repeated here: the five-layer
  architecture + cross-layer join rule (`raw → clean → enrich → dw → metric → qube`), the
  **ConfigurationService / never-hardcode-environment** rule, and the hard constraints (`.yml`
  only; rerun `make create-dag-files` after a declaration edit; Forno run mandatory before merge).
  **Read this first for any DAG/SQL/modeling work.**
- **Other `.cursor/rules/*.mdc`** — structured, path-scoped rules: `core.mdc` / `dag_build.mdc`
  (full DAG Builder reference), `naming_cheatsheet.mdc` / `naming_conventions.mdc`,
  `sql_conventions.mdc`, `databricks_conventions.mdc`, `emr_compatibility.mdc`,
  `data_quality_tests.mdc`, `governance_metadata.mdc`, `python_conventions.mdc`,
  `testing_conventions.mdc`, `people/people_domain.mdc`, …
- **`.cursor/skills/<name>/SKILL.md`** — task playbooks, shared by both clients: Cursor reads
  `.cursor/skills/` natively, Claude Code reads the same files through the `.claude/skills`
  symlink. **Invoke by name (`/create-dag`) in either client**, or read the `SKILL.md` directly.
  Examples: `setup-local-environment`, `create-dag`, `run-dag-locally`, `create-metadata-files`,
  `fix-ci-failure`, `generate-unit-test`, `create-or-update-pr`, `review-pr`, `trino`,
  `find-stale-dags`, `map-table-usage`, `pipeline-health-report`, `people-*`, …
  A skill folder must sit **one level** under `.cursor/skills/`, its YAML `name` must match the
  folder, and `description` must stay under 1024 characters — otherwise Claude Code skips it
  silently. See `docs/cursor_ai_guide.md` §6.
- **`README.md`** — install, dev container, local Airflow, useful `make` targets.
- **`docs/cursor_ai_guide.md`** and **`docs/business_contribution_guide.md`** — contribution workflows.
