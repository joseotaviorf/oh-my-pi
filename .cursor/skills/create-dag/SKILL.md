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

## Step 1b — Normalize DAG name based on layer

**CRITICAL**: Before creating any files, normalize the DAG name according to layer-specific naming conventions. The normalized name must be used consistently in:
- The folder name: `dags/{line}/{normalized_dag_name}/`
- The declaration file name: `{normalized_dag_name}_declaration.yml`
- The `dag.name` field inside the declaration YAML

### Normalization rules by layer

| Layer | Prefix Pattern | User Input Examples | Normalized Name |
|-------|---------------|---------------------|-----------------|
| **dw** | `dw_<dag_name>` | `rent_contracts` → `dw_rent_contracts`<br>`dw_rent_contracts` → `dw_rent_contracts` (no change) | Always starts with `dw_` |
| **enrich** | `enrich_<dag_name>` | `people_core` → `enrich_people_public`<br>`enrich_people_public` → `enrich_people_public` (no change) | Always starts with `enrich_` |
| **core** | `core_<dag_name>` | `contract` → `core_contract`<br>`core_contract` → `core_contract` (no change) | Always starts with `core_` |
| **metric** | `metric_<business_context>__<dag_name>` | `rent__contracts` → `metric_rent__contracts`<br>`metric_rent__contracts` → `metric_rent__contracts` (no change)<br>`rent contracts` → ask user for business_context | Always starts with `metric_` and uses `__` separator |
| **reverse** | `reverse_<dag_name>` | `webhelp_access` → `reverse_webhelp_access`<br>`reverse_webhelp_access` → `reverse_webhelp_access` (no change) | Always starts with `reverse_` |
| **raw** / **clean** (excluding gsheets) | No prefix required | Use as provided (e.g., `pin_core`, `ebdb_contract`) | No normalization needed |
| **raw (gsheets)** | `gsheets_<business_context>` | `cross` → `gsheets_cross`<br>`gsheets_for_sale` → `gsheets_for_sale` (no change) | Always starts with `gsheets_` followed by business domain |

### Normalization algorithm

1. **Check if user-provided name already matches layer pattern:**
   - DW: If name starts with `dw_`, use as-is
   - Enrich: If name starts with `enrich_`, use as-is
   - Core: If name starts with `core_`, use as-is
   - Metric: If name starts with `metric_` and contains `__`, use as-is
   - Reverse: If name starts with `reverse_`, use as-is
   - **gsheets workflow**: If name starts with `gsheets_`, use as-is

2. **If name doesn't match pattern, add appropriate prefix:**
   - DW: Prepend `dw_` to the user-provided name
   - Enrich: Prepend `enrich_` to the user-provided name
   - Core: Prepend `core_` to the user-provided name
   - Metric: Prepend `metric_` and ensure `__` separator exists (ask user for business_context if not clear)
   - Reverse: Prepend `reverse_` to the user-provided name
   - **gsheets workflow**: Format as `gsheets_{business_context}` where `{business_context}` is the business domain from Step 1

3. **Special cases:**
   - For metric layer, if user provides name without `__`, ask: "What is the business context? (e.g., rent, sale, fintech)" and format as `metric_{business_context}__{rest_of_name}`
   - For raw/clean layers (excluding `gsheets`): No normalization needed — these layers don't require layer prefixes in the DAG name (e.g., `pin_core`, `ebdb_contract` are valid as-is)
   - **For `gsheets` workflow type** (layer: raw): Normalize to `gsheets_{business_context}` where `{business_context}` is the business domain from Step 1 (e.g., `cross` → `gsheets_cross`, `for_sale` → `gsheets_for_sale`, `growth` → `gsheets_growth`). If user provides `gsheets_` prefix already, use as-is.

### Examples

| User Request | Layer | Normalized Name | Notes |
|-------------|-------|-----------------|-------|
| "rent_contracts" | dw | `dw_rent_contracts` | Added `dw_` prefix |
| "dw_rent_contracts" | dw | `dw_rent_contracts` | Already correct, no change |
| "people_core" | enrich | `enrich_people_core` | Added `enrich_` prefix |
| "enrich_people_core" | enrich | `enrich_people_core` | Already correct, no change |
| "contract" | core | `core_contract` | Added `core_` prefix |
| "core_contract" | core | `core_contract` | Already correct, no change |
| "rent__contracts" | metric | `metric_rent__contracts` | Added `metric_` prefix |
| "metric_rent__contracts" | metric | `metric_rent__contracts` | Already correct, no change |
| "webhelp_access" | reverse | `reverse_webhelp_access` | Added `reverse_` prefix |
| "reverse_webhelp_access" | reverse | `reverse_webhelp_access` | Already correct, no change |
| "pin_core" | raw/clean | `pin_core` | No normalization (raw/clean don't require layer prefix) |
| "cross" | raw/clean (gsheets) | `gsheets_cross` | Added `gsheets_` prefix with business context |
| "gsheets_for_sale" | raw/clean (gsheets) | `gsheets_for_sale` | Already correct, no change |
| "for_rent" | raw/clean (gsheets) | `gsheets_for_rent` | Added `gsheets_` prefix with business context |

**After normalization, use `normalized_dag_name` for all file paths and YAML fields.**

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

Path: `dags/{line}/{normalized_dag_name}/{normalized_dag_name}_declaration.yml`

Use `.yml` — never `.yaml`.

**IMPORTANT**: Use `normalized_dag_name` (from Step 1b) for both the folder name and file name.

### 2a — Derive `custom_schema`

**IMPORTANT for DW layer**: Before deriving `custom_schema`, ask the user:
> "Should this DAG use a custom schema different from the normalized name? For example, `dw_listing` could use `custom_schema: public` instead of `custom_schema: listing`. If yes, what should the custom_schema be?"

**Normalization rule for DW custom_schema**: If the user specifies a custom schema value:
- If the value starts with `dw_`, strip the prefix (e.g., `dw_public` → `public`)
- The system will automatically prepend `dw_` when creating the schema, so `custom_schema: public` becomes `dw_public` in the metastore
- If the value doesn't start with `dw_`, use it as-is

If the user specifies a custom schema, normalize it using the rule above. Otherwise, apply the default derivation rules below.

| Layer | Rule | Example |
|-------|------|---------|
| **DW** | **Default**: Strip `dw_` prefix from normalized name<br>**User override**: Normalize user-specified custom_schema (strip `dw_` if present) | Default: `dw_rent_contracts` → `custom_schema: rent_contracts`<br>Override: `dw_person` → `custom_schema: public` (user-specified, creates `dw_public`)<br>Normalization: User types `dw_public` → normalize to `custom_schema: public` |
| **Metric** | Use business line (before `__`) | `metric_rent__contracts` → `custom_schema: rent` |
| **Multiple CDC DAGs, same source DB** | All share the source DB name | `ebdb_house`, `ebdb_agent` → both `custom_schema: ebdb` |
| **Migration / test** | Append `_test` | `ebdb_condo_test` → `custom_schema: ebdb_test` |
| **gsheets** (raw/clean layers) | Always `gsheets` | `gsheets_cross` → `custom_schema: gsheets`<br>`gsheets_for_sale` → `custom_schema: gsheets` |
| **Enrich** | Strip `enrich_` prefix from normalized name | `enrich_people_core` → `custom_schema: people_core` |
| **Core** | Strip `core_` prefix from normalized name | `core_contract` → `custom_schema: contract` |
| **Reverse** | Strip `reverse_` prefix from normalized name | `reverse_webhelp_access` → `custom_schema: webhelp_access` |
| **Raw / clean** (excluding gsheets) | Same as normalized_dag_name (omit the key) | — |

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
  name: "{normalized_dag_name}"         # Use normalized name from Step 1b (no "bietlejuice." prefix)
  owner: "Data Engineering"            # from DAGOwnerEnum
  catchup: false
  schedule_interval: None
  schedule_start_date: "2024, 1, 1"
  documentation:
    dag_purpose: "Brief description of what this DAG does."

workflow:
  layer: "{layer}"
  type: "{workflow_type}"
  custom_schema: "{derived_schema}"    # see 2a above; omit if same as normalized_dag_name
  default_extraction_type: full         # Only for query_delta, custom_ingestion, and core_model workflows (default: full; user can change to incremental if needed)
  default_partitions: []               # Only for query_delta, custom_ingestion, and core_model workflows (default: empty; user should add partitions if tables are partitioned)

cluster:
  type: "databricks_16_4_med_general_cluster"   # most common; adjust per 2b
  databricks_conn_id: databricks_new_env         # or databricks_new for metric/reverse
```

**IMPORTANT:**
- **`default_extraction_type: full`** — Include this field only for workflows that support it:
  - ✅ `query_delta` (enrich, dw, clean layers)
  - ✅ `custom_ingestion` (raw layer)
  - ✅ `core_model` (core layer)
  - ❌ `cdc`, `database_pull`, `api_ingestion`, `gsheets` — do NOT include
- **`default_partitions: []`** — Include this field only for the same workflows listed above. After creating the declaration file, inform the user (see Step 2d below).

Add other workflow-specific parameters from the `dag_build` rule as needed (e.g. `tables_customization`, `extra_query_template_params`, `merge_on`).

### 2d — Post-creation notes

**Only for workflows that support `default_extraction_type` and `default_partitions`** (query_delta, custom_ingestion, core_model): After creating the declaration file, inform the user about partition configuration:

> "The declaration file includes `default_partitions: []` by default. If your tables will be partitioned (e.g., by `year`, `month`, `day`), please update `default_partitions` to include those partition columns (e.g., `default_partitions: [year, month, day]`). Individual tables can override the default via `tables_customization.{table_name}.partitions`."

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

Path: `dags/{line}/{normalized_dag_name}/queries/{layer}/{table_name}.sql`

### Source-layer priority for SQL creation

When creating SQL for new DAGs, prioritize upstream layers as follows:

| Target layer | Preferred source layers | Avoid by default | Exception |
|---|---|---|---|
| **enrich** | `clean` and `enrich` | any direct `raw` read | No exception — `raw` is only for clean layer |
| **dw** | **`enrich` first** | `raw` / `clean` direct reads | Other `dw` only for explicit datamart DAGs |
| **metric** | **`dw` first** | datamart `dw` tables as primary source | Use non-datamart DW models as the default source |

### Skeleton for `query_delta` — enrich layer
```sql
SELECT
    source_col AS target_col
    -- when normalizing source names, use explicit aliases:
    -- source_table.client_id AS id_client
    -- source_table.created_at AS ts_created
    -- source_table.contract_date AS dt_contract
    -- add more columns here
FROM
    datalake_source_clean.source_table AS source_table
WHERE
    1 = 1
```

### Skeleton for `query_delta` — clean layer (normalize source names)
```sql
SELECT
    source_table.client_id AS id_client,
    source_table.created_at AS ts_created,
    DATE(source_table.created_at) AS dt_created,
    source_table.contract_date AS dt_contract
    -- add more normalized columns here
FROM
    datalake_source_raw.source_table AS source_table
WHERE
    1 = 1
```

**Alias guidance:** For identifiable source names, normalize to model naming conventions:
- IDs: `*_id` → `id_*` (e.g., `client_id AS id_client`)
- Timestamps: `ts_<past_tense_when_possible>` (e.g., `created_at AS ts_created`)
- Dates: `dt_<past_tense_when_possible>` (e.g., `signed_date AS dt_signed`)
- If past tense is not natural, use semantic fallback (e.g., `contract_date AS dt_contract`)

### Skeleton for `query_delta` — dw layer (prefer enrich as source)
```sql
SELECT
    source_col AS target_col
    -- add more columns here
FROM
    datalake_source_enrich.source_table AS source_table
WHERE
    1 = 1
```

### Skeleton for metric layer (prefer DW as source)
```sql
SELECT
    source_col AS target_col
    -- add more columns here
FROM
    dw_business_schema.source_table AS source_table
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

Path: `dags/{line}/{normalized_dag_name}/metadata/{layer}/{table_name}.yml`

Every SQL file **must** have a matching metadata YAML. See the `governance_metadata` rule for full schema.

**Lineage format:** `{database}.{table}.{column}` where `{database}` is the full metastore name (e.g., `datalake_person_clean`, `datalake_ebdb_clean`, `dw_rent`), not the source database schema name.

Minimal skeleton:

```yaml
---
database_name: "{layer}_{custom_schema}"
table_name: "{table_name}"
description: "At least 10 characters describing this table."
domain: "{business_domain}"         # Derived from business domain (see mapping below)
owner: "your.email@quintoandar.com.br"
columns:
  column_name:
    lineage:
      - source_database.source_table.source_column
    description: "Column description (min 10 chars)."
```

**Domain mapping** — Map the business domain (from Step 1) to the valid domain value:

| Business Domain (folder name) | Domain Value |
|-------------------------------|--------------|
| `for_rent` | `For Rent` |
| `for_sale` | `For Sale` |
| `fintech` | `Fintech` |
| `agents` | `Agents` |
| `people` | `People` |
| `growth` | `Growth` |
| `support_and_service` | `Support and Service` |
| `3p_partners` | `3P Partners` |
| `cross` | `Cross` |
| `governance` | `Governance` |
| `mlops` | `MLOps` |
| `platform` | `Platform` |
| `qcx` | `QCX` |
| `tech_platform` | `Tech Platform` |
| `data_science` | `Data Science` |

**Valid domains:** `3P Partners`, `Agents`, `Cross`, `Data Science`, `For Rent`, `For Sale`, `Governance`, `Growth`, `MLOps`, `People`, `Platform`, `QCX`, `Support and Service`, `Tech Platform`

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
      - datalake_person_clean.person.cpf
    description: "Brazilian individual taxpayer identification number (CPF)."
    personal_data_classification: personal
  racial_origin:
    lineage:
      - datalake_person_clean.person.racial_origin
    description: "Racial or ethnic origin self-declared by the person."
    personal_data_classification: sensitive
```

---

## Step 5 — Validate

```bash
make validate-dag-declaration-files dag_name={normalized_dag_name}
make validate-metadata-files-content
```

Fix any errors before proceeding.

## Step 6 — Optional: data quality

If data quality checks are needed, create:
`dags/{line}/{normalized_dag_name}/data_quality/{layer}/{table_name}.yml`

Use this template (adjust validations to what makes sense for the table):

```yaml
table_name: {schema_name}.{table_name}   # fully-qualified; schema = layer + custom_schema
alert_channel: "#alerts-de-airflow-dags"
table_level_validations:
  has_size:
    greater_than: 0
    severity_level: Error          # Error and Warning categorize alert registration; neither blocks the pipeline
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

Add a `data_quality` file for all tables where data correctness is business-critical. 

**Note on `severity_level`:** Both `Error` and `Warning` serve only to categorize how alerts are registered; neither actually blocks the pipeline. Use `Error` for critical validations that require immediate attention, and `Warning` for less critical checks that should be monitored but don't require immediate action.

## Checklist

- [ ] DAG name normalized according to layer conventions (Step 1b)
- [ ] Declaration file named `{normalized_dag_name}_declaration.yml` (`.yml` not `.yaml`)
- [ ] Folder at `dags/{line}/{normalized_dag_name}/`
- [ ] `dag.name` field matches `normalized_dag_name` exactly
- [ ] SQL files in `queries/{layer}/`
- [ ] Metadata YAML for every SQL file in `metadata/{layer}/`
- [ ] `make validate-dag-declaration-files` passes
- [ ] `make validate-metadata-files-content` passes
- [ ] Task count under 100 (job cluster workflows)
- [ ] Columns containing personal data carry `personal_data_classification` in metadata
- [ ] Sensitive/Highly Personal columns have `table_privileges` set in the DAG declaration
- [ ] LGPD legal basis confirmed (with the data owner) for any `sensitive` column
- [ ] `default_extraction_type: full` included in workflow section (only for query_delta, custom_ingestion, core_model workflows; user can change to `incremental` if needed)
- [ ] `default_partitions: []` included in workflow section (only for query_delta, custom_ingestion, core_model workflows; user informed to update if tables are partitioned)

**Additional checks for CDC DAGs:**
- [ ] Kafka Connect + S3-Sink connectors already running (data confirmed in S3)
- [ ] `source_schema` set correctly (Postgres: `"public"`; MySQL: database name)
- [ ] All `tables_customization` keys match source DB casing exactly
- [ ] All source tables have primary keys
- [ ] `debezium_signal` is NOT in `tables_customization`
- [ ] DAG runs successfully on Forno Airflow before merging PR
