# Source-layer policy validation

PR-scoped validation that DAGs only reference tables from metastore layers allowed for their **output** layer (`workflow.layer` in `*_declaration.yml`). **Domains do not change the policy.**

User-facing log lines use the prefix **`Source validation`** (success, warning, and failure) so CI output reads consistently.

## Validation outcomes (exit code and stdout)

Rules below match what the script prints in CI and locally. Allowed layers come from [`layer_policy_matrix.py`](layer_policy_matrix.py) (`ALLOWED_SOURCE_LAYERS_BY_OUTPUT`).

### When validation succeeds (clean)

- **Exit code:** `0`
- **When:** No disallowed table references are found in the scanned DAG(s) for the current mode, **or** the DAG is skipped (e.g. `workflow.type` in `skip_workflow_types`).
- **Stdout:** A short success banner only (no per-file table inventory by default), for example:

```text
========================================================================
✅ Source validation passed!
========================================================================
```

This applies to: a lenient PR with a clean DAG; a strict PR whose **new** source files are clean and the rest of the DAG has no violations; and audit mode (`-a`) when there are no issues.

### When validation passes with warnings

- **Exit code:** `0` (merge **not** blocked)
- **When:**
  - **Strict PR** (new declaration or new source artifacts): new files are clean, but **pre-existing** files under the same DAG still reference disallowed layers; **or**
  - **Lenient PR** (only edits to existing source files or non-source paths): the full DAG scan finds any disallowed reference.
- **Stdout:** A warning block with DAG name, `workflow.layer`, allowed layers, then **`Invalid table usage in **edited** files:`** (meaning “not introduced as new source artifacts in this PR”), grouped by **repo-relative file path** under **`Table with error:`**, then a pointer to `layer_policy_matrix.py`. After all warning blocks, a short closing line:

```text
✅ Source validation passed (with warnings above).
```

### When validation fails (strict)

- **Exit code:** `1`
- **When:** In **strict** mode, at least one **new** source artifact (or a new DAG declaration that triggers strict mode together with new sources) references a table whose layer is not allowed for this DAG’s output layer.
- **Stdout:** A failure block with **`❌ Source validation failed in the following files`**, DAG context, **`Invalid table usage in **new** files:`** (grouped by file path), **`Resolve the issue(s) above to enable merging!`**, and the matrix pointer. **No** trailing success banner.

### When validation fails and also reports warnings

- **Exit code:** `1`
- **When:** Strict failure on **new** files **and** the same DAG still has violations in **pre-existing** files.
- **Stdout:** The **failure** block (new files) is printed **first**, then the **warning** block (edited / pre-existing files), then the process exits. There is **no** final “passed” line.

## Strict vs lenient (profile `dags`)

- **Strict (merge can be blocked):** The PR **adds** a new `*_declaration.yml` or **adds** new source files under the DAG (`queries/**/*.sql`, or under `spark_jobs/` with `.sql` / `.yaml` / `.yml` / `.py`). Only violations in those **new** files fail CI.
- **Lenient:** The PR only **modifies** existing files (e.g. `M` on SQL/conf/py) or changes non-source paths (metadata, etc.). The **full DAG** is scanned; violations are **warnings** only.
- **Skipped DAGs:** `workflow.type` values under `skip_workflow_types` in [`profiles/dags.yml`](profiles/dags.yml) skip table extraction for that DAG.

Other details:

- **Scope (branch mode):** Only DAG roots touched by the PR diff (`origin/master...HEAD` on feature branches).
- **Transactional lake:** Schemas `datalake_*_transactional` are layer **`transactional`**. DAGs with `workflow.layer: enrich` or `core` may reference them (see matrix). Metadata YAML is **not** scanned.

## Profiles

- **`dags`** ([`profiles/dags.yml`](profiles/dags.yml)) — default for CI. `path_prefix: dags/`, `dag_root_segment_count: 3`, SQL glob `queries/**/*.sql`, Spark conf under `spark_jobs/`, Python `spark.table("schema.table")` literals when `scan_python_spark_table_literals` is true.
- **`core`** ([`profiles/core_spark.yml`](profiles/core_spark.yml)) — optional: `path_prefix: dags/core/` for branch mode under `dags/core/`. [`extract_all_tables_for_core_dag`](dag_reference_extractors.py) remains for tests/tooling.

### Modules

- [`sql_table_extractor.py`](sql_table_extractor.py) — SQL parsing (sqlglot, Spark dialect).
- [`output_messages.py`](output_messages.py) — Banners and grouped violation text.

## Local usage

- **PR-style:** `make validate-source-layer-policy` (uses `CI_COMMIT_BRANCH`).
- **All DAGs:** `make validate-source-layer-policy-all` (audit; lenient semantics).
- **Core only:** `make validate-source-layer-policy-all-core`.

Direct CLI (add **`-v`** for extra diagnostics, e.g. per-DAG summary when violations exist):

```bash
PYTHONPATH=. python3 scripts/ci_cd/source_layer_validation/validate_source_layer_policy.py --profile dags -b "$(git branch --show-current)"
PYTHONPATH=. python3 scripts/ci_cd/source_layer_validation/validate_source_layer_policy.py --profile dags -a -v
```

## Known limits

- Dynamic `spark.table(expr)` without string literals is not detected.
- Heavy Jinja/bracket templating may require extending `normalize_sql_for_table_extraction`.
- Git renames are compared with `--no-renames` (treated as delete + add; **added** paths use strict rules).
