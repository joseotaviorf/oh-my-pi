---
name: emr-migration-v2
description: >
  Transpile Databricks SQL to EMR Spark 3.5 using SQLGlot + LLM conventions,
  validate syntax, generate three validation DAGs (Twin/EMR/Comparison).
  Only SQLs with Databricks-only constructs are transpiled.
---

# EMR Migration v2

End-to-end pipeline: transpile Databricks SQL → validate on real clusters →
fix failures → generate validation DAGs → trigger → compare results → create PRs.

## End-to-end runbook

### Phase 1 — Transpile

Converts Databricks-only SQL to Spark 3.5 using SQLGlot. Only files with
Databricks-only constructs are transpiled; clean SQL passes through unchanged.

```bash
# Single DAG:
uv run --directory packages/bietlejuice-compiler python \
  .cursor/skills/emr-migration-v2/transpile.py \
  --scope fintech/enrich_velo

# Multiple DAGs:
uv run --directory packages/bietlejuice-compiler python \
  .cursor/skills/emr-migration-v2/transpile.py \
  --scope fintech/enrich_velo,agents/enrich_agent

# Transpile + generate DAGs in one step:
uv run --directory packages/bietlejuice-compiler python \
  .cursor/skills/emr-migration-v2/transpile.py \
  --scope fintech/enrich_velo --generate-dags
```

Output: transpiled SQL under `dags/platform/migration_emr_{scope_id}/queries/migration/`.

### Phase 2 — Validate + fix (loop)

Validates transpiled SQL through the full chain: SQLGlot parse → Databricks
EXPLAIN → EMR EXPLAIN. Failing files are fixed by the IDE (you/Cursor/Claude Code).

```bash
# Step 1: validate (writes .git/validation_report.json)
uv run --no-project --with sqlglot,requests,boto3 python \
  .cursor/skills/emr-migration-v2/validate_transpiled_sql.py \
  --databricks-cluster-id 0724-123456-abcdef \
  --emr-cluster-id j-XXXXX

# Step 2: inspect failures
uv run --no-project python \
  .cursor/skills/emr-migration-v2/fix_from_report.py

# Step 3: ask the IDE to fix
#   "fix the failing SQL files from the validation report"

# Step 4: re-validate → repeat until 0 failures
```

Alternative — batch fix via Anthropic API (no IDE needed):
```bash
ANTHROPIC_API_KEY=sk-ant-... \
uv run --no-project --with sqlglot,requests,boto3,anthropic python \
  .cursor/skills/emr-migration-v2/validate_transpiled_sql.py \
  --fix --fix-retries 3 \
  --databricks-cluster-id 0724-123456-abcdef \
  --emr-cluster-id j-XXXXX
```

### Phase 3 — Generate DAGs

After validation+fix, generate DAGs **without re-running** mechanical transpilation
(which would overwrite your fixes):

```bash
uv run --directory packages/bietlejuice-compiler python \
  .cursor/skills/emr-migration-v2/transpile.py \
  --scope fintech/enrich_velo --generate-dags --skip-transpile
```

Use `--skip-transpile` whenever Phase 2 has already validated/fixed the SQL.
Omit it only if you're running transpile + DAG generation in a single step
(Phase 1 shortcut: `--generate-dags` without `--skip-transpile`).

Creates three DAGs per scope under `dags/platform/`:

| DAG | Runtime | Purpose |
|-----|---------|---------|
| `migration_twin_{scope_id}` | Databricks | Run ORIGINAL queries → capture metrics → S3 |
| `migration_emr_{scope_id}` | EMR | Run TRANSPILED queries → capture metrics → S3 |
| `migration_compare_{scope_id}` | Databricks | Compare twin vs emr metrics → verdict → S3 |

Then regenerate DAG files:
```bash
make create-dag-files
```

### Phase 4 — Trigger + compare

Deploy to Forno, then trigger via Airflow API:

```bash
uv run python .cursor/skills/emr-migration-v2/trigger_migration_dags.py \
  --max-parallel 32
```

Triggers twin + emr DAG pairs in batches. Compare DAGs fire automatically
via Airflow Datasets when both twin and emr complete.

### Phase 5 — Results + PRs

Fetch comparison verdicts from S3 and create grouped PRs:

```bash
# Auto-discover all scopes, group PRs by domain:
uv run --no-project --with boto3,pyyaml,sqlglot python \
  .cursor/skills/emr-migration-v2/results.py \
  --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br

# Filter to specific domains:
uv run --no-project --with boto3,pyyaml,sqlglot python \
  .cursor/skills/emr-migration-v2/results.py \
  --domain growth,fintech \
  --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br

# Dry run (print verdicts and grouping, no PRs):
uv run --no-project --with boto3,pyyaml,sqlglot python \
  .cursor/skills/emr-migration-v2/results.py \
  --artifacts-bucket s3://artifacts.s3.data.quintoandar.com.br \
  --dry-run
```

Creates one PR per domain/verdict category (passed vs review-needed).

---

## Reference

### Detected constructs (transpiled automatically)

- `QUALIFY` → CTE + WHERE with ROW_NUMBER
- `IFF(cond, a, b)` → `IF(cond, a, b)`
- `DECODE(expr, k1, v1, ...)` → CASE WHEN
- `DATEDIFF(unit, start, end)` 3-arg → `DATEDIFF(end, start)` 2-arg
- `column:key` variant access → STRUCT/MAP/JSON rewrite
- `col::TYPE` → `CAST(col AS TYPE)`
- `SELECT * EXCEPT(...)` → explicit column list
- `RANGE_JOIN` / `SKEW` hints → stripped

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

### PRs created by results.py

| PR | Content | Tone |
|----|---------|------|
| `emr-migration/transpile/{domain}-passed` | PASS/WARN tables | Safe to merge — validated equivalent |
| `emr-migration/transpile/{domain}-failed` | FAIL tables | Needs manual review |

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
