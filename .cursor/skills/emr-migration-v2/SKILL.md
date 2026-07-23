---
name: emr-migration-v2
description: >
  Transpile Databricks SQL to EMR Spark 3.5 using SQLGlot + LLM conventions,
  validate syntax, generate three validation DAGs (Twin/EMR/Comparison).
  Only SQLs with Databricks-only constructs are transpiled.
---

# EMR Migration v2

Transpiles Databricks-only SQL constructs to EMR Spark 3.5 using SQLGlot, applies
repo conventions via LLM, validates syntax, and generates three validation DAGs.

## Invocation

```
# Single DAG
migrate fintech/enrich_docx

# Multiple DAGs (comma-separated list)
migrate fintech/enrich_docx,agents/enrich_agent,growth/enrich_attribution

# Entire domain
migrate --domain fintech
```

## Workflow

### 1. Discover SQL files

Parse the scope argument. For each DAG in the scope:
- Find SQL files under `dags/{domain}/{dag_name}/queries/{layer}/*.sql`
- Validate the DAG path exists

### 2. Detect & transpile (only Databricks-only constructs)

For each SQL file, check for Databricks-only constructs using `needs_transpilation()`.
**Only files with detected constructs are transpiled.** Clean SQL passes through unchanged.

Detected constructs (from `emr_compatibility.mdc`):
- `QUALIFY` → CTE + WHERE with ROW_NUMBER
- `IFF(cond, a, b)` → `IF(cond, a, b)`
- `DECODE(expr, k1, v1, ...)` → CASE WHEN
- `DATEDIFF(unit, start, end)` 3-arg → `DATEDIFF(end, start)` 2-arg
- `column:key` variant access → appropriate STRUCT/MAP/JSON rewrite
- `col::TYPE` → `CAST(col AS TYPE)`
- `SELECT * EXCEPT(...)` → explicit column list

**Transpilation pipeline:**

1. **SQLGlot** (`databricks` → `spark` dialect) handles mechanical rewrites
2. **LLM convention enforcement** — review transpiled SQL against:
   - `.cursor/rules/sql_conventions.mdc` (UPPERCASE keywords, snake_case, CTEs, formatting)
   - `.cursor/rules/emr_compatibility.mdc` (dual-runtime safety)
   - `.cursor/skills/databricks-emr-sql-lint/RECIPES.md` (specific rewrite patterns)
3. **Syntax validation** — `validate_spark_syntax()` parses with SQLGlot in Spark dialect
4. On syntax failure: retry LLM fix once, then mark table as FAIL

### 3. Generate three DAGs

Using `dag_generator.py`, render Jinja templates into `dags/platform/`:

| DAG | Runtime | Purpose |
|-----|---------|---------|
| `migration_twin_{scope_id}` | Databricks | Run ORIGINAL queries, capture count + schema + profile → S3 |
| `migration_emr_{scope_id}` | EMR | Run TRANSPILED queries, capture count + schema + profile → S3 |
| `migration_compare_{scope_id}` | Databricks (minimal) | Compare metrics, write verdict → S3 |

Profile includes **null counts** and **xxhash64 checksums** per column.

The Comparison DAG is triggered by Airflow Datasets from both Twin and EMR DAGs.

### 4. Report

Print transpilation summary per table:
- `[+]` PASS — transpiled and syntax-validated
- `[-]` SKIP — already dual-runtime compatible (no constructs found)
- `[!]` FAIL — transpilation or syntax validation failed

## S3 output structure

```
s3://{artifacts_bucket}/emr-migration/runs/{run_id}/
  manifest.json
  twin/{domain}/{dag_name}/{table}.json    # Databricks metrics
  emr/{domain}/{dag_name}/{table}.json     # EMR metrics
  verdicts/{domain}/{dag_name}/
    {table}.json                           # Per-table verdict
    summary.json                           # Aggregate verdict
```

## Verdict schema

Each per-table verdict JSON:
```json
{
  "version": 1,
  "run_id": "uuid",
  "table_name": "table_name",
  "count_match": true,
  "count_twin": 42567,
  "count_emr": 42567,
  "count_delta_pct": 0.0,
  "schema_match": true,
  "schema_issues": [],
  "null_count_match": true,
  "checksum_match": true,
  "profile_issues": [],
  "verdict": "PASS"
}
```

Verdict values:
- `PASS` — count, schema, null counts, and checksums all match
- `WARN` — count within 5% tolerance or safe type widening or minor checksum drift
- `FAIL` — count >5% mismatch, incompatible schema, null count mismatch, or checksum mismatch

The aggregate `summary.json` has `pr_gate_eligible: true` when zero FAILs.

## Results command

After the comparison DAGs have run, use `results.py` to fetch verdicts from S3 and
create PRs that replace original SQL with transpiled versions.

### Invocation

```bash
# Single DAG
uv run --no-project --with boto3,pyyaml python \
  .cursor/skills/emr-migration-v2/results.py \
  --scope fintech/enrich_velo \
  --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br

# Multiple DAGs
uv run --no-project --with boto3,pyyaml python \
  .cursor/skills/emr-migration-v2/results.py \
  --scope fintech/enrich_velo,fintech/enrich_docx \
  --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br

# Dry run (print verdicts only)
uv run --no-project --with boto3,pyyaml python \
  .cursor/skills/emr-migration-v2/results.py \
  --scope fintech/enrich_velo \
  --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br \
  --dry-run

# With assume role (cross-account S3)
uv run --no-project --with boto3,pyyaml python \
  .cursor/skills/emr-migration-v2/results.py \
  --scope fintech/enrich_velo \
  --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br \
  --assume-role-arn arn:aws:iam::123456789:role/MyRole
```

### What it does

1. Reads `manifest.json` from each comparison DAG directory to get the run ID
2. Downloads `summary.json` and per-table verdict JSONs from S3
3. Partitions tables by verdict:
   - **Validated** (PASS/WARN) — transpiled SQL produces equivalent results
   - **Needs review** (FAIL) — transpiled SQL diverges from baseline
4. For each group, creates a branch and PR:
   - Copies transpiled SQL from `migration_emr_{scope}/queries/migration/` into the
     source DAG's `queries/{layer}/`, replacing the original
   - PR body includes a validation results table (counts, schema, nulls, checksums)
     and S3 artifact references

### PRs created

| PR | Content | Tone |
|----|---------|------|
| `emr-migration/validated/{slug}` | PASS/WARN tables | Safe to merge — validated equivalent |
| `emr-migration/needs-review/{slug}` | FAIL tables | Recommendation — needs manual review |

Both PRs contain the transpiled SQL. The validated PR is merge-ready; the needs-review
PR includes detailed issue breakdowns for each failing table.

## Key files

| File | Purpose |
|------|---------|
| `packages/bietlejuice-compiler/src/bietlejuice/transpiler/databricks_to_spark.py` | SQLGlot transpiler |
| `packages/bietlejuice-compiler/src/bietlejuice/transpiler/syntax_validator.py` | Syntax validation |
| `packages/bietlejuice-runtime/src/bietlejuice/migration/metric_capture_job.py` | PySpark metric capture |
| `packages/bietlejuice-runtime/src/bietlejuice/migration/comparison_job.py` | Comparison + verdict |
| `.cursor/skills/emr-migration-v2/transpile.py` | Transpilation orchestrator |
| `.cursor/skills/emr-migration-v2/dag_generator.py` | DAG template renderer |
| `.cursor/skills/emr-migration-v2/results.py` | Fetch verdicts + create PRs |
| `.cursor/skills/emr-migration-v2/models.py` | Shared dataclasses |
| `.cursor/skills/emr-migration-v2/s3_paths.py` | S3 path conventions |
| `.cursor/skills/emr-migration-v2/templates/` | Jinja templates for the three DAGs |

## Convention references

When applying LLM convention enforcement, load these files:
- `.cursor/rules/sql_conventions.mdc`
- `.cursor/rules/emr_compatibility.mdc`
- `.cursor/skills/databricks-emr-sql-lint/RECIPES.md`
- `.cursor/skills/databricks-emr-sql-lint/COMPATIBLE.md`
