---
name: create-dag
description: Scaffold a complete new Airflow DAG in bi-etl-ejuice. Creates the declaration YAML, SQL query skeletons, governance metadata YAML, and optionally data_quality files. Use when the user asks to create a new DAG, add a new pipeline, or set up a new table ingestion.
---

# Create a New DAG

## Step 1 — Determine layer and workflow type

Ask (or infer from context):
- **Business domain** (e.g. `for_rent`, `fintech`, `people`) → determines `dags/{line}/` folder
- **Layer**: `raw`, `enrich`, `dw`, `metric`, `reverse`, `core`, `qube`
- **Workflow type** (per layer):

| Layer | Recommended workflow | Alternatives |
|-------|---------------------|--------------|
| raw (DB CDC via Debezium) | `cdc` | `dms_cdc` (AWS DMS) |
| raw (pull-based DB ingestion) | `database_pull_delta` | `database_pull` (deprecated) |
| raw (REST API) | `api_ingestion` | — |
| raw (custom Spark job) | `custom_ingestion` | — |
| raw (Google Sheets) | `gsheets` | — |
| clean | `query_delta` | — |
| enrich / dw | `query_delta` | `query_view`, `query` (deprecated) |
| metric | `query` (interactive cluster) | `query_delta` (job cluster) |
| core | `core_model` | `query_delta` |
| reverse | `load`, `access`, or `load_access` | — |
| qube | use the `create-qube-spec` skill instead | — |

**If `workflow_type = cdc`, follow the CDC-specific steps below before Step 2.**

---

## CDC-specific steps (only for `type: cdc`)

### CDC Step A — Verify prerequisites

Before writing any YAML, confirm:
1. Kafka Connect (Debezium) connector is deployed and running for this database.
2. S3-Sink connector is deployed and routing data to `s3://5a-datalake-incoming-{forno/prod}/{database}/`.
3. Data is visible in S3 for the tables to be ingested.

If connectors are not yet deployed, stop here and direct the user to the Backstage software templates ("Debezium Kafka Connect and Connector" + "S3-Sink Kafka Connect and Connector"). The DAG cannot be used until the infrastructure exists.

### CDC Step B — Set `source_schema` and `source_database`

Ask the database type, then apply the correct mapping:

| Database type | `source_schema` | `source_database` |
|---------------|----------------|-------------------|
| **Postgres** | PostgreSQL schema name — usually `"public"` | The database name (e.g. `"ebdb"`) |
| **MySQL** | The database name (same as source_database) | The database name (e.g. `"retsuko"`) |

Also ask: is this a **migration DAG** running side-by-side with an existing ingestion? If yes:
- Append `_test` to the dag_name (e.g. `ebdb_condo_test`)
- Set `custom_schema` to the destination test schema (e.g. `"ebdb_test"`)

### CDC Step C — Collect table list

For each table to ingest:
- **Table name** — ask for the exact name from the source database (case-sensitive: `Usuario` ≠ `usuario`)
- **Primary keys** — confirm the table has a primary key (required; tables without PKs cannot be replicated)
- **Clean table name** — if different from the raw name
- **z_order_by** — columns used frequently in WHERE/JOIN for query optimization

Do NOT include `debezium_signal` in the tables list — it belongs in the connector config only.

### CDC Step D — Adding tables to an existing CDC DAG?

If the user wants to add tables to an already-deployed CDC DAG (not create a new one):
1. First, update the Kafka connector via Backstage (`kafka-connect-add-tables` template).
2. Wait for the Woodpecker pipeline to confirm the connector is running.
3. Only then update the DAG declaration's `tables_customization`.
4. Consider triggering a Debezium incremental snapshot for historical data (tables < 10M rows).

---

## Step 2 — Create the declaration file

Path: `dags/{line}/{dag_name}/{dag_name}_declaration.yml`

Use `.yml` — never `.yaml`.

### 2a — Derive `custom_schema`

| Layer | Rule | Example |
|-------|------|---------|
| **DW** | Strip `dw_` prefix | `dw_losses` → `custom_schema: losses` |
| **Metric** | Use business line (before `__`) | `metric_rent__contracts` → `custom_schema: rent` |
| **Multiple CDC DAGs, same source DB** | All share the source DB name | `ebdb_house`, `ebdb_agent` → both `custom_schema: ebdb` |
| **Migration / test** | Append `_test` | `ebdb_condo_test` → `custom_schema: ebdb_test` |
| **Enrich / raw / clean / other** | Same as dag_name (omit the key) | — |

### 2b — Choose cluster type

Ask: does the DAG need non-standard node types, Spot instances, or custom JARs/libraries?

- **No** → use a named preset. Most common choice: `databricks_16_4_med_general_cluster`.
  - Metric layer: use `databricks_16_4_med_io-general_cluster` with `databricks_conn_id: databricks_new`.
- **Yes** → use `custom_cluster` (see full template in `dag_build` rule).

| Layers | `databricks_conn_id` |
|--------|---------------------|
| enrich, dw, raw (CDC/custom) | `databricks_new_env` |
| metric, qube, reverse | `databricks_new` |

### 2c — Declaration skeleton

```yaml
dag:
  name: "{dag_name}"                    # no "bietlejuice." prefix
  owner: "Data Engineering"            # from DAGOwnerEnum
  catchup: false
  schedule_interval: None
  schedule_start_date: "2024, 1, 1"
  documentation:
    dag_purpose: "Brief description of what this DAG does."

workflow:
  layer: "{layer}"
  type: "{workflow_type}"
  custom_schema: "{derived_schema}"    # see 2a above; omit if same as dag_name

cluster:
  type: "databricks_16_4_med_general_cluster"   # most common; adjust per 2b
  databricks_conn_id: databricks_new_env         # or databricks_new for metric/reverse
```

Add workflow-specific parameters from the `dag_build` rule (e.g. `default_extraction_type`, `tables_customization`, `extra_query_template_params`, `merge_on`).

For `type: cdc`, use this skeleton (filled using CDC Steps A–C above):
```yaml
workflow:
  layer: "raw"
  type: "cdc"
  database_type: "postgres"       # or "mysql"
  source_schema: "public"         # Postgres schema OR MySQL database name
  source_database: "ebdb"         # Postgres database name (omit for MySQL)
  custom_schema: "ebdb"           # destination schema in datalake
  dbutils_secret_key: "EBDB_DB"   # default: <CUSTOM_SCHEMA>_DB (uppercase); omit if default
  lineage_product_database_name: "ebdb"  # omit if tag-level lineage only is needed
  has_hive_sync: true
  tables_customization:
    exact_table_name_from_source:  # CASE-SENSITIVE
      clean_table_name: "clean_name"   # if different from raw name
      z_order_by: ["user_id"]
```

## Step 3 — Create SQL query files

Path: `dags/{line}/{dag_name}/queries/{layer}/{table_name}.sql`

Skeleton for `query_delta` (enrich/dw):
```sql
SELECT
    source_col AS target_col
    -- add more columns here
FROM
    source_database.source_table
WHERE
    1 = 1
```

For incremental tables, add date filtering:
```sql
WHERE
    updated_at >= '{{ load_start_date }}'
    AND updated_at < '{{ load_end_date }}'
```

## Step 4 — Create governance metadata files

Path: `dags/{line}/{dag_name}/metadata/{layer}/{table_name}.yml`

Every SQL file **must** have a matching metadata YAML. See the `governance_metadata` rule for full schema. Minimal skeleton:

```yaml
---
database_name: "{layer}_{custom_schema}"
table_name: "{table_name}"
description: "At least 10 characters describing this table."
domain: "For Rent"         # must be a valid domain from the enum
owner: "your.email@quintoandar.com.br"
columns:
  column_name:
    lineage:
      - source_database.source_table.source_column
    description: "Column description (min 10 chars)."
```

## Step 4b — Personal data classification

For every column in every metadata YAML created in Step 4, assess whether it contains data about an identifiable natural person. If so, set `personal_data_classification` to the appropriate tier.

### Quick classification reference

| Tier | Key examples |
|---|---|
| `sensitive` | racial/ethnic origin, political opinion, religion, gender identity, sexual orientation, union membership, health data (ICD, neurodiversity, disability, pre-existing conditions, toxicological exams, DPS, body metrics), biometric data (facial recognition, fingerprints, voice recognition) |
| `highly_personal` | bank statement, credit history, credit score, IRPF, INSS benefit statement, criminal background, personal/corporate credit or debit card number, photo with ID document |
| `personal` | full name, CPF, date of birth, RG, passport, CNH, PIS/PASEP, voter ID, personal/corporate email, personal/corporate phone, residential/corporate address, geolocation, contract number, QuintoAndar account info, salary, age, marital status, device ID, IP address, browsing history, cookies, image/photo, service history |

### Decision rules

1. For each column, scan its name and description against the table above.
2. If a column matches `sensitive`:
   - **Warn the user** before proceeding. State which LGPD legal basis applies (e.g. explicit consent, legitimate interest for employment) or ask the user to confirm.
   - Add `personal_data_classification: sensitive` to the metadata YAML.
   - Add or recommend `table_privileges` in the DAG declaration to restrict access to authorised groups (e.g. `"prod-read-only": ["SELECT"]` for a named group only).
   - If the table will feed a metric or qube output, confirm that `privacy.k_anonymity ≥ 5` will be set in the qube metric declaration.
3. If a column matches `highly_personal`:
   - Recommend adding `table_privileges` in the declaration and confirm with the user before proceeding.
   - Add `personal_data_classification: highly_personal` to the metadata YAML.
   - Suggest hashing or masking the column before promoting beyond the clean layer.
4. If a column matches `personal`:
   - Add `personal_data_classification: personal` to the metadata YAML. No extra access-control step required, but note the classification.
5. Apply the same classification consistently across all layers for the same logical column (raw → clean → enrich → dw).

### Example — metadata column with classification

```yaml
columns:
  cpf:
    lineage:
      - ebdb_public.person.cpf
    description: "Brazilian individual taxpayer identification number (CPF)."
    personal_data_classification: personal
  racial_origin:
    lineage:
      - ebdb_public.person.racial_origin
    description: "Racial or ethnic origin self-declared by the person."
    personal_data_classification: sensitive
```

---

## Step 5 — Validate

```bash
make validate-dag-declaration-files dag_name={dag_name}
make validate-metadata-files-content
```

Fix any errors before proceeding.

## Step 6 — Optional: data quality

If data quality checks are needed, create:
`dags/{line}/{dag_name}/data_quality/{layer}/{table_name}.yml`

Use this template (adjust validations to what makes sense for the table):

```yaml
table_name: {schema_name}.{table_name}   # fully-qualified; schema = layer + custom_schema
alert_channel: "#alerts-de-airflow-dags"
table_level_validations:
  has_size:
    greater_than: 0
    severity_level: Error          # Error blocks the pipeline; Warning logs only
column_level_validations:
  {primary_key_col}:
    is_complete:
      severity_level: Error
    is_unique:
      severity_level: Error
  {important_col}:
    is_complete:
      severity_level: Error
  {nullable_col}:
    has_completeness:
      greater_than: 0.95           # fraction non-null (allows up to 5% nulls)
      severity_level: Warning
```

Add a `data_quality` file for all tables where data correctness is business-critical. Use `severity_level: Error` only for hard constraints that should block the pipeline.

## Checklist

- [ ] Declaration file named `{dag_name}_declaration.yml` (`.yml` not `.yaml`)
- [ ] Folder at `dags/{line}/{dag_name}/`
- [ ] SQL files in `queries/{layer}/`
- [ ] Metadata YAML for every SQL file in `metadata/{layer}/`
- [ ] `make validate-dag-declaration-files` passes
- [ ] `make validate-metadata-files-content` passes
- [ ] Task count under 100 (job cluster workflows)
- [ ] Columns containing personal data carry `personal_data_classification` in metadata
- [ ] Sensitive/Highly Personal columns have `table_privileges` set in the DAG declaration
- [ ] LGPD legal basis confirmed (with the data owner) for any `sensitive` column

**Additional checks for CDC DAGs:**
- [ ] Kafka Connect + S3-Sink connectors already running (data confirmed in S3)
- [ ] `source_schema` set correctly (Postgres: `"public"`; MySQL: database name)
- [ ] All `tables_customization` keys match source DB casing exactly
- [ ] All source tables have primary keys
- [ ] `debezium_signal` is NOT in `tables_customization`
- [ ] DAG runs successfully on Forno Airflow before merging PR
