# Ruff — configuration and scope

Shared configuration lives in the repo root [`pyproject.toml`](../pyproject.toml). Ruff walks up the directory tree; there is no `ruff.toml`. [`packages/emr-cli/pyproject.toml`](../packages/emr-cli/pyproject.toml) only adds isort `known-first-party = ["emr"]`.

## Global settings

| Setting | Value | Notes |
|---------|-------|-------|
| `line-length` | 88 | Matches Python conventions in `.cursor/rules/python_conventions.mdc` |
| `target-version` | `py310` | Aligned with DBR / Airflow |
| `extend-exclude` | `.cursor` | Cursor rules/skills not linted |
| `builtins` | `spark`, `dbutils`, `udf` | Databricks-injected globals in Spark jobs |

## Selected rules (`select`)

| Code | Family | Summary |
|------|--------|---------|
| E4 | pycodestyle imports | Import layout (e.g. E402) |
| E7 | pycodestyle statements | Statement style |
| E9 | pycodestyle runtime | Syntax / runtime errors |
| F | Pyflakes | Unused imports, undefined names, f-strings, etc. |
| I | isort | Import sorting |
| UP | pyupgrade | Syntax modernization (partially disabled) |

## Globally ignored upgrades (`ignore`)

| Rule | Reason |
|------|--------|
| UP006, UP035 | Keep `List` / `Dict` for older DBR consumers |
| UP007, UP045 | Keep `Union` / `Optional` instead of `\|` syntax |

## Per-file ignores

| Pattern | Ignored | Why |
|---------|---------|-----|
| `dags/**/*.py` | F403, F405, E712, E722 | Star imports; legacy `== True/False`; bare `except` |
| `packages/bietlejuice-compiler/scripts/**/*.py` | E402 | CLI/script import layout |
| `.../__dags_template__.py` | F821 | DAG builder template placeholders |

## Makefile targets

| Target | Scope | CI (Woodpecker) |
|--------|--------|-----------------|
| `make check-style` | `packages/*/src`, `packages/*/test`, `packages/bietlejuice-compiler/scripts` | Yes (`check-style-python`) |
| `make check-style-dags` | `dags/` | Yes (`check-style-dags-python`) |
| `make lint` / `make fix-style` | Same as `check-style` | — |
| `make lint-dags` / `make fix-style-dags` | Same as `check-style-dags` | — |

Invocation: `uv run --project packages/bietlejuice-compiler` (Ruff **0.15.13** from workspace lock).

`packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/__dags_template__.py` is excluded via `RUFF_EXCLUDE`.

## Baseline (pre–Part 2 fix, for reference)

Counts before the Part 2 big-bang format/lint pass:

| Path | `.py` files | Format drift | Lint issues |
|------|-------------|--------------|-------------|
| `dags/` | ~303 | ~263 files | ~745 (~580 auto-fixable) |
| `packages/bietlejuice-compiler/scripts/` | ~58 | ~32 files | ~155 (~153 auto-fixable) |
Both targets must pass locally and in Woodpecker (`check-style-python`, `check-style-dags-python`).

## Related tooling

- **SQL:** SQLFluff via `make check-sql` / `make lint-sql` on `dags/` only.
- **Types:** `make type-check` (`ty`) on package `src/`; CI `failure: ignore`.
