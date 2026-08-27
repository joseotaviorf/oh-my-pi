# ADR 0001: Qube dimension and measure sources beyond Core

## Status

Accepted

## Date

2026-08-21

## Context

Qube dimensions and measures are built from declarative YAML specs. Today, when `source.table` is omitted, the runtime defaults to `core_{entity}.{entity}` and always resolves explicit short names through the Core database mapping in `Config.get_table_path("core", ...)`.

That design made early Qube adoption simple, but it blocks legitimate use cases where attribute logic should read from governed Clean, Enrich, DW, or Metric tables while still publishing into `qube_dimensions` / `qube_measures`.

We also need a configurable **universe** table for the closed-world `include_all_entities` join. That join must stay at the business-entity grain even when the event source lives in another layer.

Cross-layer governance already exists in `bietlejuice-compiler` via `layer_policy_matrix.py`. Qube output DAGs must remain compatible with that policy and with DataHub lineage-based dependency inference (planned follow-up).

## Decision

### 1. Source resolution contract

Dimension and measure specs may declare sources in either form:

**Fully qualified reference (backward compatible)**

```yaml
source:
  table: enrich_visit.visit_events
  date_expr: "..."
```

**Structured reference (preferred for new specs)**

```yaml
source:
  layer: enrich
  source_schema: enrich_visit
  table_name: visit_events
  date_expr: "..."
```

Resolution rules:

- If `source_schema` and `table_name` are set, they form `{source_schema}.{table_name}`.
- Else if `table` is set, it is used as `{schema}.{table}`.
- Else default to `core_{entity}.{entity}` (unchanged behavior).
- `entity_id_col` still defaults to `id_{entity}`.
- Layer is taken from `source.layer` when provided; otherwise inferred from the schema prefix.
- **Raw layer sources are rejected at runtime.** Allowed layers: `clean`, `enrich`, `dw`, `metric`, `core`, `qube`.

### 2. Universe table (closed-world join)

When `include_all_entities: true`, the builder left-joins aggregated values onto supported entity IDs:

```yaml
source:
  table: enrich_visit.visit_events
  universe_table: core_visit.visit
  universe_entity_id_col: id_visit
  date_expr: "..."
```

Defaults: `universe_table` = `core_{entity}.{entity}`, `universe_entity_id_col` = `entity_id_col`.

### 3. DAG dependencies

Qube dimension/measure DAGs infer upstream dependencies from `source.table` (and
`universe_table`) via the compiler dependency generator (`make automate-dependencies`).
Layer-policy CI validates the same references against `layer_policy_matrix`.

## Implementation plan

| PR | Scope |
|----|--------|
| PR1 | ADR, source_resolver, spec extensions, dimension/measure runtime, tests |
| PR2 | Compiler validation (`bietlejuice.base.dependencies.qube_source_extractor`); DAG dependency inference from source tables |
| PR3 | Spec migrations and documentation |

## Operational notes (EMR pilot)

Qube jobs on **EMR** read source tables with **OSS Delta Lake** (Spark 3.5 / EMR 7.12). That
reader needs a **replayable transaction log** on S3: JSON commits from version 0, or a **classic**
checkpoint (`NNNNN.checkpoint.parquet` + `_last_checkpoint`) that lets replay start mid-log.

**Databricks Runtime** on the same table can keep writing and reading even when OSS cannot:
DBR 16.4 ships paired `.crc` version-checksum files alongside each commit (present on forno
`core_visit.visit` v8–18). OSS Delta on EMR does not use those checksums and still must replay
from v0 or a classic checkpoint.

### Forno example: `core_visit.visit` (2026-08)

Recursive listing of `s3://5a-datalake-forno/core/core_visit/visit/_delta_log/`:

| Finding | Detail |
|--------|--------|
| JSON commits | **v8–v18 only** (no `000…00.json`) |
| Classic checkpoints | **None** (`_last_checkpoint` 404) |
| v2 / uuid checkpoints, `_sidecars/` | **None** |
| `.crc` files | Present for v8–18 (DBR version checksums) |
| Parquet data | Present under table prefix |

EMR Qube measure DAGs fail with `DELTA_TRUNCATED_TRANSACTION_LOG` at v18. Other forno core
tables (e.g. `core_contract.contract`) have classic checkpoints and are OSS-readable.

### Root cause (do not blame VACUUM or log retention)

**Neither VACUUM nor Delta log-retention cleanup can produce this state:**

- VACUUM removes **data** files, not `_delta_log` JSON.
- Log retention deletes old commits **only after** a newer checkpoint exists.

So **v0–v7 missing with zero checkpoints** implies **external deletion** of log objects — e.g. an
S3 lifecycle rule on the prefix, or manual `rm`. `_last_vacuum_info` on the prefix is a **red
herring** for explaining missing commits.

**Platform actions (in order):**

1. **Investigate deletion** — S3 lifecycle rules and access logs on
   `…/core/core_visit/visit/_delta_log/` (and parent prefixes). If a rule ate checkpoints, a
   regenerated checkpoint will be deleted again until the rule is fixed.
2. **Regenerate a classic checkpoint** from Databricks once deletion is stopped — not “restore
   Parquet data”. A normal MERGE from `bietlejuice.core_visit` is **not** guaranteed to write one:
   Delta emits classic checkpoints every `delta.checkpointInterval` commits (default **10**). At
   v18, a single successful run that only adds **v19** likely writes **no** checkpoint; **v20**
   would. After any core_visit run, re-list `_delta_log/` before re-testing EMR. If still no
   checkpoint, the platform ask stands (second commit, `OPTIMIZE`, or an explicit checkpoint
   action on Databricks).
3. **EMR smoke read** after a checkpoint exists. If OSS still fails, check table features written
   by DBR (deletion vectors, CDF) against the EMR Delta version.

### Verification command

```bash
aws s3 ls s3://<bucket>/<prefix>/<schema>/<table>/_delta_log/ --recursive
```

Do not re-trigger EMR measure DAGs against a source whose log starts above 0 with no checkpoint.
