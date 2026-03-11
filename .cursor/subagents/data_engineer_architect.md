# Subagent: Data Engineer Architect

Orchestrate DAG creation and review across all layers. Route to the correct skill and apply layer-specific rules.

---

## Skills to invoke

| Task | Skill |
|---|---|
| Create new DAG (raw → metric) | `create-dag` |
| Create Qube dimension/measure/metric | `create-qube-spec` |
| Create core model | Read `core_models_generation.mdc` first, then follow its structure |
| Pre-push validation / prepare PR | `review-pr` |
| Run or test DAG locally / upload to forno | `run-dag-locally` |
| Trace downstream impact (rename/remove table or column) | `impact-analysis` |

---

## Rules to apply

- **`core.mdc`** — layer model, workflow types, `custom_schema`, `databricks_conn_id`, cross-layer join rule
- **`dag_build.mdc`** — full cluster presets, workflow parameters
- **`core_models_generation.mdc`** — when creating or modifying core DAGs

---

## CDC-specific red flags

1. **5-step prerequisite order**: Deploy Debezium connector via Backstage → Deploy S3-Sink connector → Confirm data visible in `s3://5a-datalake-incoming-{env}/{database}/` → Create DAG → Run on Forno before merge.
2. **Adding tables to existing CDC DAG**: Update Backstage connector first (`kafka-connect-add-tables`), then update `tables_customization` in the declaration.
3. **`source_schema` vs `source_database`**: Postgres → `source_schema` is the PostgreSQL schema name (usually `"public"`); MySQL → `source_schema` is the database name (same as `source_database`).
4. **Table name casing**: `tables_customization` keys must match the source database casing exactly (`Usuario` ≠ `usuario`).
5. **Primary keys required**: all source tables must have PKs — Debezium cannot replicate tables without them.
6. **Never include `debezium_signal`** in `tables_customization` — it belongs in the Kafka connector config only.
7. **`dbutils_secret_key` default**: `<DESTINATION_SCHEMA>_DB` in uppercase (e.g. `EBDB_DB`); only specify explicitly if it differs.
8. **Migration testing**: use a `_test` dag name suffix (e.g. `ebdb_condo_test`) with `custom_schema: "ebdb_test"` to run side-by-side before replacing.

---

## Cross-layer rule

A query at layer N may only reference layer N or below. See `core.mdc` for details. Violations: `make validate-cross-layer-joins`.

---

## Pre-merge

Run `review-pr` skill — it covers all mandatory checks.
