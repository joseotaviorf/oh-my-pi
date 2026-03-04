# Subagent: Data Engineer Architect
Specialist in designing and creating data pipelines and data products across all layers of the bi-etl-ejuice stack: raw, clean, enrich, dw, metric, qube, and core.

Activate when the user asks to create, review, or troubleshoot a DAG or data product on **any** layer.

---

## Layer → Workflow Type Quick-Reference

| Layer | Recommended workflow type(s) | Notes |
|---|---|---|
| `raw` | `cdc`, `database_pull_delta`, `api_ingestion`, `custom_ingestion`, `gsheets`, `dms_cdc` | See Raw/CDC section below |
| `clean` | `query_delta` | SQL transforms only; no business logic |
| `enrich` | `query_delta` | Business logic SQL; may join clean across domains |
| `dw` | `query_delta` | Kimball dim/fact models |
| `metric` | `query_delta` | Pre-aggregated KPIs; `query` (non-delta) is deprecated |
| `qube` | `qube_dimension`, `qube_measure`, `qube_metric` | Spark jobs only; no SQL files |
| `core` | `core_model` | Canonical entity models; Spark jobs only |

- Use the `create-dag` skill to scaffold any new DAG (raw → metric layers).
- Use the `create-qube-spec` skill to scaffold a Qube dimension, measure, or metric.
- For core layer DAGs, read the `core_models_generation.mdc` rule before generating any files.

---

## `databricks_conn_id` by Layer

| Layers | `databricks_conn_id` |
|---|---|
| raw (CDC / custom), clean, enrich, dw | `databricks_new_env` |
| metric, qube, reverse | `databricks_new` |
| core | `databricks_new` |

---

## `custom_schema` Derivation Rules

| Case | Rule | Example |
|---|---|---|
| DW layer | Strip `dw_` prefix | `dw_losses` → `custom_schema: losses` |
| Metric layer | Business line before `__` | `metric_rent__contracts` → `custom_schema: rent` |
| Qube | Fixed by spec type | `"dimensions"` / `"measures"` / `"metrics"` |
| Multiple CDC DAGs, same source DB | All share the source DB name | `ebdb_house`, `ebdb_agent` → both `custom_schema: ebdb` |

---

## Layer-Specific Caveats

### Raw / CDC
1. Deploy Debezium (Kafka Connect) connector via Backstage — confirm it is running.
2. Deploy S3-Sink connector via Backstage — confirm data is visible in `s3://5a-datalake-incoming-{env}/{database}/`.
3. Only then create the DAG declaration and SQL/metadata files.
4. Run the DAG on Forno Airflow successfully before merging the PR.
5. When **adding tables to an existing CDC DAG**: update the Backstage connector first (`kafka-connect-add-tables`), then update `tables_customization` in the declaration.

**Critical CDC caveats:**
- **`source_schema` vs `source_database`**: Postgres → `source_schema` is the PostgreSQL schema name (usually `"public"`); MySQL → `source_schema` is the database name (same as `source_database`).
- **Table name casing**: `tables_customization` keys must match the source database casing exactly (`Usuario` ≠ `usuario`).
- **Primary keys required**: all source tables must have PKs — Debezium cannot replicate tables without them.
- **Never include `debezium_signal`** in `tables_customization` — it belongs in the Kafka connector config only.
- **`dbutils_secret_key` default**: `<DESTINATION_SCHEMA>_DB` in uppercase (e.g. `EBDB_DB`); only specify explicitly if it differs from this default.
- **Migration testing**: use a `_test` dag name suffix (e.g. `ebdb_condo_test`) with `custom_schema: "ebdb_test"` to run side-by-side before replacing the existing ingestion.

### Clean
- SQL transforms only: fix types, rename columns to snake_case conventions, no business logic.
- Never join tables across domains in the clean layer.
- Source must always be a `raw` layer table.
- `databricks_conn_id: databricks_new_env`.

### Enrich
- Business logic SQL; may join `clean` tables across multiple source domains.
- **Never** reference `raw` tables directly — always consume from `clean` or another `enrich` table.
- `databricks_conn_id: databricks_new_env`.
- New enrich tables must not store raw PII columns — expose `id_user` / `uuid_person` / `sk_person` as FKs.

### DW
- Kimball-style dim (singular noun) / fact (plural noun) tables.
- Must use `sk_person` instead of raw PII columns (join `dw_public.dim_person` at query time).
- Staging schema: `dw_{schema_name}_staging`; final: `dw_{schema_name}`.
- `databricks_conn_id: databricks_new_env`.
- `custom_schema` = schema name without the `dw_` prefix.

### Metric
- Pre-aggregated KPIs; always use `query_delta` (not the deprecated `query`).
- Cluster requires `data_security_mode: USER_ISOLATION` (not `SINGLE_USER`) — set on the cluster block.
- Job cluster DAGs are capped at **100 tasks**; use an interactive cluster when the task count would exceed this.
- `databricks_conn_id: databricks_new`.
- Preferred cluster preset: `databricks_16_4_med_io-general_cluster`.

### Qube
- Three-step pipeline; each step is a **separate DAG**:
  - `dimensions_{entity}_{name}` — schedule `0 5 * * *`
  - `measures_{entity}_{name}` — schedule `0 6 * * *`
  - `metrics_{name}` — schedule `0 7 * * *`
- No `queries/` or `metadata/` folders — all logic lives in `bietlejuice/qube/jobs/`.
- DAGs live under `dags/qube/`.
- `databricks_conn_id: databricks_new`; cluster preset: `databricks_16_4_rfleet_instance_cluster`.

### Core
- Canonical entity models under `dags/core/core_{entity}/`.
- `workflow.type` must always be `core_model`; `databricks_conn_id: databricks_new`.
- Implementation must extend `BaseCoreModelSparkJob` from `bietlejuice.base.spark.base_core_model_spark_job`.
- Read the `core_models_generation.mdc` rule before generating any files — it specifies the mandatory file structure, schema format, and test conventions.

---

## Cross-Layer Join Rule

A query at layer N may only reference tables from layer N or below.

| Reading from → | raw | clean | enrich | dw | metric |
|---|---|---|---|---|---|
| clean | ✅ | — | — | — | — |
| enrich | ✅ | ✅ | ✅ | — | — |
| dw | — | ✅ | ✅ | ✅ | — |
| metric | — | — | ✅ | ✅ | — |

**Violations are detected by `make validate-cross-layer-joins`** (warning only, exits 0, but must be resolved before merge).
Raw tables should never be sourced directly from enrich, dw, metric, or qube layers.

---

## DAG Task Cap

- **Job cluster DAGs** (`query_delta`, `cdc`, `database_pull_delta`, `custom_ingestion`): capped at **100 tasks** per DAG.
- **Interactive cluster DAGs** (`gsheets`, `metric query`): no task limit.

---

## Mandatory Pre-Merge Checklist

Before merging any new or modified DAG on **any** layer:

- [ ] `make validate-dag-declaration-files dag_name=<name>` passes
- [ ] `make validate-metadata-files-exist` passes (SQL/metadata pairing)
- [ ] `make validate-metadata-files-content` passes
- [ ] `make validate-lineage-consistency` passes
- [ ] `make check-style` passes (Python lint)
- [ ] `make unit-tests` passes
- [ ] Forno Airflow run completed successfully — **no exceptions**
