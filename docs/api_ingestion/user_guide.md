# DAG Builder - API Ingestion Workflow

The **api_ingestion** workflow is a declarative framework for building DAGs that ingest data from REST APIs into the data lake. Instead of writing a bespoke Spark job per integration, you configure the workflow via YAML: endpoints, authentication, pagination, and rate limiting. Shared runtime code performs HTTP calls, basic retries, and raw-layer writes; some declaration fields are reserved or only partially wired (called out explicitly below).

This document describes the **api_ingestion** workflow currently implemented in the DAG Builder.  
It focuses only on what exists in code today, plus known limitations.

---

## Index

- [Raw: API Ingestion](#raw-api-ingestion)
  - [Scope](#scope-what-this-workflow-is-for)
  - [Before you start](#before-you-start-read-the-api-docs)
- [How the DAG is built](#how-the-dag-is-built)
- [API ingestion DAG naming and schema](#api-ingestion-dag-naming-and-schema)
- [Parameters allowed via declaration file](#parameters-allowed-via-declaration-file)
  - [Parameter reference (workflow)](#parameter-reference-workflow)
- [tables_customization](#tables_customization-per-table)
  - [Parameter reference (tables_customization)](#parameter-reference-tables_customization)
- [`id_expansion` (per-entity fan-out)](#id_expansion-per-entity-fan-out)
  - [What is fan-out (id_expansion)?](#what-is-fan-out-id_expansion)
  - [How it works at runtime](#how-it-works-at-runtime)
  - [When to use it](#when-to-use-it)
  - [`payload_filters`](#payload_filters)
  - [Parallel fan-out (`max_workers`)](#parallel-fan-out-max_workers)
  - [`date_expansion`](#date_expansion-per-table-optional)
- [Authentication](#authentication-workflowauthentication)
  - [Parameter reference (authentication)](#parameter-reference-authentication)
- [Request params and date placeholders](#request-params-and-date-placeholders)
- [Bounded validation on EMR](#bounded-validation-on-emr)
- [Pagination](#pagination-api_policiespagination) (`none`, `offset_limit`, `page_per_page`, `cursor`)
- [Rate limiting](#rate-limiting-api_policiesrate_limiting)
- [Error handling](#error-handling-api_policieserror_handling)
- [YAML examples](#yaml-examples-supported-features)
- [Output: raw table schema](#output-raw-table-schema)
- [Reference DAGs](#reference-dags)
- [Known limitations](#known-limitations-current-mvp)
- [Contributing](#contributing)

## Raw: API Ingestion

The purpose of this workflow is to ingest data from **REST APIs** into the **raw** data lake layer.

Instead of creating custom code for each integration, you declare:

- **what** endpoint to call (`endpoint_path`)
- **how** to authenticate (`authentication`)
- **how** to paginate (`api_policies.pagination`)
- **how** to rate limit between pages (`api_policies.rate_limiting`)
- **which** query params to send (including date placeholders)

### Scope (what this workflow is for)

- **Layer**: Raw (primary), optionally followed by **Clean** tasks if you provide clean queries.
- **HTTP method**: **GET** only.
- **Data model**: API responses are stored as **raw JSON strings** in a single column (`payload` by default).

### Before you start (read the API docs)

To configure a new ingestion you must read the **documentation of the API you are integrating** to identify:

- **Authentication**: which strategy applies (none/basic/oauth2 client credentials), which secrets/fields you need, and whether tokens expire.
- **Pagination**: none vs offset/limit vs cursor/PIT, where the cursor lives (headers vs params) and where “next cursor” is returned in the response.
- **Rate limiting**: whether the API has limits, which headers it returns (if any), and if you need a fixed delay between requests.
- **Filtering/query params**: which parameters are required and how to request an incremental window (dates), ordering, expansions, etc.
- **Response shape**: whether results come as `list`, or inside `results` / `data` / `items`, and which field contains the record timestamp if you want partitioning by API time.

Before configuring the ingestion, we suggest testing the API endpoint manually using Postman (or similar tools) to understand how authentication, pagination, and response formatting work in practice.

---

## How the DAG is built

For each key under `workflow.tables_customization`, the builder creates a raw ingestion task that:
- Makes HTTP requests to the configured API endpoint (handling authentication, pagination, and rate limiting)
- Processes and normalizes the API response data
- Writes the data as JSON strings to the raw data lake layer, automatically adding partition columns (`year`, `month`, `day`, `ts_load`) to the schema (physical partitioning can be configured via the `partitions` parameter)

If there are matching clean queries in the DAG package (`queries/clean/<clean_table>.sql`), the workflow will also create clean tasks for those tables and chain them after the raw ingestion.

### API ingestion DAG naming and schema

For **`api_ingestion`**, the **DAG identifier** must follow a packaging rule:

- **`dag.name`**, the folder under `dags/{line}/`, and the declaration filename **`{dag_name}_declaration.yml`** must all use the same `dag_name`, and that name **must end with `_api`** (e.g. `currency_api`).
- **Reason:** the hatch build config in `packages/bietlejuice-runtime/pyproject.toml` includes only `**/*_api_declaration.y*ml` so the declaration is shipped inside the **Python wheel**. On Databricks, `load_api_ingestion_raw` resolves the YAML from the installed package (or local/S3 paths). If the filename does not match that pattern, the declaration may be missing at runtime after install.

**Not tied to `_api`:** **`workflow.custom_schema`** and the resulting **raw metastore schema** (`datalake_{custom_schema}_raw` when that pattern applies) are **independent**. You may use a short or legacy schema name without `_api` (e.g. `dag.name: rates_api` with `custom_schema: currency`) as long as naming conventions for the lake layer are satisfied.

---

## Parameters allowed via declaration file

This section describes the parameters you can configure in the `workflow` section of your DAG declaration file (`<dag_name>_declaration.yml`). For general information about building DAGs, including cluster configurations and DAG-level settings, see the [DAG Builder - User Guide](https://docs.google.com/document/d/1zq5_S0M9FuExHKsujpow6HqZxkzgSubQlDLaSOiwXCQ/edit?tab=t.0).

### Required

- **layer** (string): must be `raw`
- **type** (string): must be `api_ingestion`
- **api_base_url** (string or dict): base URL for the API  
  - If `string`: used for all environments
  - If `dict`: must include at least one env key (e.g. `prod`, `forno`). The runtime env is read from `ENVIRONMENT` (default: `forno`)
- **tables_customization** (dict): maps “table names” to endpoint configs
- **authentication** (dict) must be present either:
  - once at workflow level (`workflow.authentication`), or
  - per-table (`workflow.tables_customization.<table>.authentication`)

### Optional

- **payload_column_name** (string): column that will store the raw JSON string
  - Default: `payload`
- **http_user_agent** (string): optional `User-Agent` for API and OAuth2 token HTTP calls (see parameter reference)
- **http_headers** (dict): optional static HTTP headers merged onto the `requests` session (workflow map, then per-table overlay; table wins on the same key). Quote values in YAML. Do **not** use this for `User-Agent` — that stays **`http_user_agent`**.
- **date_format_mask** (string): `strftime` mask used to format `load_start_date` / `load_end_date` placeholders into strings (e.g. `%Y%m%d`)
  - Table-level override: `workflow.tables_customization.<table>.date_format`
- **extra_query_template_params** (dict): DAG-wide `load_start_date` / `load_end_date` Jinja templates. Override per table with `tables_customization.<table>.extra_query_template_params` (same replace-then-fill rules as query/CDC).
- **api_policies** (dict): `rate_limiting`, `pagination`, `error_handling`
- **alert_channel** (string): accepted in the declaration schema; today `APIConfigurationLoader` only **logs** that a channel was configured — it is **not** wired to `BaseAPIClient` yet
- **load_spark_job** (string): defaults to `load_api_ingestion_raw`
- **spark_job_prefix** (string): defaults to `base`
- **spark_job_arguments** (list): default list is filled on the declaration for consistency with other workflows; **`LoadAPIRawTaskCreator` builds the real Spark positional arguments in code** (see `bietlejuice/base/airflow/task_creators/load_api_raw_task_creator.py`) and does **not** render this template

### Parameter reference (workflow)

Below are the workflow-level parameters **implemented/consumed by the current MVP**.

- **`layer`** string (required): must be `raw`.
- **`type`** string (required): must be `api_ingestion`.
- **`api_base_url`** string or dict (required): API base URL.
  - If `string`: used for all environments.
  - If `dict`: keys are environments (e.g. `prod`, `forno`). Runtime env is read from `ENVIRONMENT` (default: `forno`).
- **`http_user_agent`** string (optional): custom HTTP `User-Agent` on the `requests` session and on OAuth2 token requests. Omit to keep library defaults.
- **`http_headers`** dict (optional): static HTTP headers (`Header-Name: value`) applied to the API `requests` session after auth/`Accept`. Per-table `tables_customization.<table>.http_headers` overlays the workflow map (table wins on the same key; omitted table keys inherit workflow). Quote values (e.g. `"2023-06-01"`). `User-Agent` still uses **`http_user_agent`**.
- **`credentials_scope`** string (optional): Databricks Secrets scope to read API credentials from (e.g. `people`).
  - If omitted, falls back to `DATABRICKS_SECRET_SCOPE` (default: `quintoandar`).
- **`tables_customization`** dict (required): mapping of table names → per-table config.
- **`authentication`** dict (required\*): auth configuration (see “Authentication”).
  - Must be present either at workflow level or per table (`tables_customization.<table>.authentication`).
  - Cannot be `{}` (empty dict).
- **`api_policies`** dict (optional): request behavior overrides.
  - **`api_policies.pagination`** dict (optional): if omitted, a single request is made. If `{}` → validation error.
  - **`api_policies.rate_limiting`** dict (optional): supports `fixed_delay` (sleep between pages) and optional **`initial_delay_seconds`** (sleep once in the Spark job before the first HTTP call — see `load_api_ingestion_raw.py`).
  - **`api_policies.error_handling`** dict (optional):
    - **`retry_policy`** dict (optional): only **`retries`** is applied today (mapped to `max_retries` on `BaseAPIClient`). Keys like **`delay`**, **`backoff_factor`**, and **`status_forcelist`** are **logged** if present but **not** passed into urllib3 (the client uses fixed defaults inside `BaseAPIClient`).
    - **`non_fatal_status_codes`** list[int] (optional, default: `[]`): accepted in YAML and **logged** at client creation; **not** enforced by `BaseAPIClient` yet (HTTP errors still fail the job like any other non-2xx after retries).
- **`payload_column_name`** string (optional, default: `payload`): JSON payload column name (can be overridden per table).
- **`date_format_mask`** string (optional, default: `null`): `strftime` mask used when replacing `load_start_date` / `load_end_date` placeholders (workflow-level alias **`date_format`** is also accepted by the Cerberus schema and resolved the same way in `get_initial_params`).
- **`extra_query_template_params`** dict (optional): DAG-wide Jinja templates for the Spark `load_start_date` / `load_end_date` CLI args (the values substituted into `params` placeholders). `BaseWorkflow` copies these into the DAG execution context.
  - **`load_start_date`** string (optional, default): `{{ get_date_param(dag_run, data_interval_start | ds, 'load_start_date') }}`
  - **`load_end_date`** string (optional, default): `{{ get_date_param(dag_run, data_interval_start | ds, 'load_end_date') }}`
  - Per-table override: `tables_customization.<table>.extra_query_template_params` **replaces** this dict for that table (same as query/CDC). Missing `load_start_date` / `load_end_date` are filled from the DAG execution context. Only those two keys are passed to Spark; other extra keys are ignored.
- **`execution_timeout_hours`** float (optional, default: `2`): task timeout in hours (table-level override supported).
- **`default_extraction_type`** string (optional, default: `full`): default extraction type for tables.
- **`default_partitions`** list (optional, default: `[]`): default partitions list (commonly `[year, month, day]`).
- **`raw_inner_dependencies`** dict (optional, default: `{}`): dependency graph to control **raw** task ordering.
  - Keys are table names; values are lists of table names that must finish before the key starts.
  - Useful to serialize calls when an API has token invalidation/race conditions under parallelism.
- **`inner_dependencies`** dict (optional, default: `{}`): alias for `raw_inner_dependencies` (backward-compatible with other workflows).
- **`clean_inner_dependencies`** dict (optional, default: `{}`): dependency graph to control **clean** task ordering (same format as `raw_inner_dependencies`).
- **`custom_schema`** string (optional, default: dag name): used by TableAttributes schema inference.
- **`load_spark_job`** string (optional, default: `load_api_ingestion_raw`): Spark job name used by raw load tasks.
- **`spark_job_prefix`** string (optional, default: `base`): spark_jobs folder prefix (`/spark_jobs/<prefix>/`).
- **`spark_job_arguments`** list (optional): if omitted, defaults are set by `RawAPIIngestionWorkflow` for declaration parity only; the running task still uses the fixed argument list from `LoadAPIRawTaskCreator` (see above).

\* `authentication` is required, but can be defined at **workflow** level OR per **table**.

---

## `tables_customization` (per “table”)

Each entry defines one API call pattern.

### Required

- **endpoint_path** (string): path appended to `api_base_url`

### Optional

- **params** (dict): query parameters sent on the request
  - Any param value can use placeholders:
    - `load_start_date` → formatted start date
    - `load_end_date` → formatted end date
- **date_filter_column** (string): JSON field name inside the payload used for partitioning
  - If set, the job extracts `$.<date_filter_column>` from the payload and uses it to compute `year/month/day` partitions.
  - If not set, partitions are computed from the default `ts_load` logic.
- **clean_table_name** (string): if you have clean queries, this controls the expected clean query filename
- **authentication** (dict): overrides workflow-level authentication for this table
- **api_policies** (dict): overrides workflow-level policies for this table

> Note: some keys seen in existing DAGs (e.g. `merge_schema`) are **not used** by the current implementation (see limitations).

### Parameter reference (tables_customization)

Each entry under `tables_customization` is a dictionary keyed by the **raw table name**:

- **`tables_customization.<table>`** dict (required): table config.
  - **`tables_customization.<table>.endpoint_path`** string (required): endpoint path appended to `api_base_url`.
  - **`tables_customization.<table>.params`** dict (optional, default: `{}`): query parameters for the request.
    - Supports placeholders `load_start_date` / `load_end_date`.
    - If omitted, the loader defaults to `after_time`/`before_time` when dates are provided.
  - **`tables_customization.<table>.authentication`** dict (required\*): overrides workflow authentication for this table.
  - **`tables_customization.<table>.http_headers`** dict (optional): overlays `workflow.http_headers` for this table (same merge rules as the workflow key).
  - **`tables_customization.<table>.api_policies`** dict (optional): overrides workflow `api_policies` for this table.
  - **`tables_customization.<table>.payload_column_name`** string (optional): overrides the payload column name.
    - Default: workflow `payload_column_name` → `payload`.
  - **`tables_customization.<table>.date_filter_column`** string (optional): JSON field name used for partitioning.
  - **`tables_customization.<table>.date_format`** string (optional): overrides `workflow.date_format_mask` for placeholders.
  - **`tables_customization.<table>.extra_query_template_params`** dict (optional): per-table `load_start_date` / `load_end_date` (and only those keys are sent to Spark). Replaces `workflow.extra_query_template_params` for this table; omitted date keys fall back to the DAG execution context. Use this when one endpoint needs a different window than the rest of the DAG (for example an exclusive vendor `ending_date` via `macros.ds_add(data_interval_start | ds, 1)`).
  - **`tables_customization.<table>.clean_table_name`** string (optional, default: `<table>`): clean query filename mapping.
  - **`tables_customization.<table>.extraction_type`** string (optional, default: workflow `default_extraction_type` → `full`).
  - **`tables_customization.<table>.partitions`** list (optional, default: workflow `default_partitions` → `[]`).
  - **`tables_customization.<table>.execution_timeout_hours`** float (optional, default: workflow `execution_timeout_hours` → `2`).
  - **`tables_customization.<table>.load_spark_job`** / **`spark_job_arguments`**: allowed in the shared declaration schema for other workflows; **`LoadAPIRawTaskCreator` always submits `load_api_ingestion_raw` with the fixed parameter list** — per-table overrides are **not** applied for `api_ingestion` today.
  - **`tables_customization.<table>.spark_job_prefix`** string (optional, default: workflow `spark_job_prefix` → `base`): **used** to locate the job under `spark_jobs/<prefix>/` (same pattern as CDC/custom raw loaders).
  - **`tables_customization.<table>.id_expansion`** dict (optional): enables **fan-out fetching** — one API call per entity ID read from an already-ingested raw source table. Supports **`param_name`** (query string), **`path_param`** (placeholder in `endpoint_path`, e.g. `requests/employees/{employeeUuid}`), and optional **`correlation_field`** for row stamping. See [id_expansion](#id_expansion-per-entity-fan-out) below.

\* Per-table `authentication` is required if workflow-level `authentication` is missing.

---

## `id_expansion` (per-entity fan-out)

### What is fan-out (id_expansion)?

In a normal `api_ingestion` configuration, the job calls **one endpoint** (optionally paginated) and writes the result set once. It represents a linear 1-to-1 relationship between the ingestion task and the API.

**Fan-out** is the opposite pattern. It is used for APIs that lack bulk endpoints and only expose data **per-entity** (e.g., instead of an endpoint for "all employee costs," the API requires you to ask for "costs for employee X").

Instead of making one call, the DAG "fans out" into dozens, hundreds, or thousands of individual HTTP requests to build a single raw table.

> **The Core Rule:** **1 ID list → N HTTP calls (or N×M if paginated) → 1 raw table**. Because the fan-out task relies on reading another table first, you MUST use `workflow.raw_inner_dependencies` to ensure the source task finishes before the fan-out begins.

### How it works at runtime

When you configure an endpoint with `id_expansion`, the framework executes the following sequence:

1. **Read source entities:** Spark reads an already-ingested raw table (defined as `source_table`, e.g., `employees`) and keeps the **latest row per entity ID** (`id_field` inside the JSON payload, ordered by `ts_load` / partition columns).
2. **Filter the list (Optional but recommended):** If `payload_filters` are configured (e.g., only `active: true`), the job filters that latest snapshot *before* collecting IDs. This prevents making HTTP calls for inactive or irrelevant entities, including stale historical rows where the entity used to match the filter.
3. **Execute HTTP Fan-out:** For every single ID collected, the job issues an independent HTTP request. It dynamically injects the ID into the URL path (`path_param`), the query string (`param_name`), or the JSON body (`json_body_field`) depending on your YAML configuration.
4. **Paginate per entity (Optional):** If pagination is configured, *each* per-entity request will paginate until exhausted before moving to the next ID. All pages across all entities are collected.
5. **Merge and Write:** The job optionally stamps each row with the `correlation_field` (so you retain a record of which ID generated which row), flattens all collected responses, and writes them together into a single raw Delta table.

### When to use it

You should configure `id_expansion` when:

- The endpoint requires a single entity ID and returns data exclusively for that entity.
- No bulk or list variant exists (omitting the ID returns an error or an empty response).
- The entity list is already available in a raw table ingested by the **same DAG**.

### YAML schema

```yaml
tables_customization:
  <table_name>:
    # With query-param ID (endpoint_path has no placeholder):
    endpoint_path: <path>
    id_expansion:
      source_table: <table>        # raw table name within the same DAG schema
      id_field: <json_field>       # JSON field to extract from payload column
      param_name: <query_param>    # query parameter name (use this OR path_param, not both)
      # correlation_field: <key>  # optional: JSON key used to stamp each row with the fan-out id
    params:
      <key>: load_start_date
    date_format: "%Y-%m-%d"

  <table_name_path_style>:
    # With path-segment ID — endpoint_path MUST contain {path_param} exactly once per segment:
    endpoint_path: "parent/{employeeUuid}/child"
    id_expansion:
      source_table: employees
      id_field: uuid
      path_param: employeeUuid
      # correlation_field: employeeUuid   # optional when API rows already use "uuid" for something else
```

### Required keys

| Key | Required | Description |
|-----|----------|-------------|
| `source_table` | yes | Name of the raw table to read entity IDs from (e.g. `employees`) |
| `id_field` | yes | JSON field path inside `payload` to extract (e.g. `uuid`, `externalId`) |
| `param_name` | yes* | Query parameter name to pass the ID (e.g. `employeeUuid`) |
| `path_param` | yes* | Placeholder name matching `{placeholder}` in `endpoint_path` (e.g. `employeeUuid` for `requests/employees/{employeeUuid}`) |
| `correlation_field` | no | JSON key used when stamping each response row with the fan-out entity id; defaults to `id_field`. Use when list items already expose `uuid` (or similar) from the API and you must not overwrite it. |
| `json_body_field` | no\* | JSON body property name for **POST** fan-out (e.g. Oitchau `employeeExternalId`). Sends `POST` with body `{ "<json_body_field>": "<entity_id>" }` per ID. When the response is a dict with a `content` array, each element is flattened to one raw row (same as list responses). **Pagination is not supported** together with `json_body_field` (configure `api_policies.pagination` only for GET-style fan-out). |
| `payload_filters` | no | List of `{ field, equals }` filters on the source raw `payload` JSON **before** collecting entity IDs (e.g. only `active: true` employees). Reduces fan-out volume without changing the endpoint. |
| `max_workers` | no | Parallel HTTP fan-out threads on the **Spark driver** (default `1`). See [Parallel fan-out (`max_workers`)](#parallel-fan-out-max_workers). |

\* Exactly one of `param_name`, `path_param`, or `json_body_field` must be provided.

### `payload_filters`

Each entry is applied as `get_json_object(payload, '$.<field>') = <equals>` on the **latest** source raw row per entity (not on the fan-out response). Boolean `equals` values are compared as lowercase strings (`true` / `false`), matching how Spark stringifies JSON booleans.

Prefer a YAML **list** of `{ field, equals }` maps. A single bare map is accepted and normalized to a one-element list. Every entry **must** include both `field` and `equals` (use `equals: null` to keep rows where the JSON field is missing).

Example — fan-out only over active OiTchau employees:

```yaml
id_expansion:
  source_table: employees
  id_field: uuid
  param_name: employeeUuid
  payload_filters:
    - field: active
      equals: true
```

### Parallel fan-out (`max_workers`)

By default (`max_workers: 1`), fan-out runs **sequentially**: one HTTP call finishes before the next starts. That is safe but slow when the entity list is large (thousands of IDs).

Setting **`max_workers` > 1** enables **parallel fan-out**:

- The job builds a task list (one task per entity ID; with `date_expansion`, one task per entity × date).
- A Python `ThreadPoolExecutor` on the **Spark driver** runs up to `max_workers` HTTP calls at once.
- OAuth token refresh is locked; HTTP GETs run concurrently (do not put a global lock around the session for the whole request).
- Failed entity calls are still logged and skipped; other tasks continue.

#### How this relates to Spark / EMR

| Expectation | Reality |
|-------------|---------|
| “More EMR core/task nodes will speed up fan-out” | **No.** Parallelism is **driver-side threads**, not Spark executor tasks. Extra cluster workers do not issue more API calls. |
| “`max_workers` uses Spark partitions” | **No.** IDs are `collect()`’d to the driver; responses accumulate in driver memory before the raw write. |
| “Any cluster size is fine” | Prefer a **memory-oriented single-node** preset so the driver has enough RAM for ID lists + buffered responses (e.g. `emr_7_12_consolidation_m_memory_single_node_fleet_cluster` / `r6g.2xlarge`). Scale up to `l`/`xl` memory single-node if the driver OOMs. |
| “Raise `max_workers` freely” | Bound by **API rate limits (429)**, task `execution_timeout_hours`, and driver CPU/memory — not by “more Spark cores”. |

**Practical guidance**

1. Start with a modest `max_workers` (e.g. 8–16); raise toward 32–64 only if wall-clock is the bottleneck and the API tolerates the concurrency.
2. Combine with `payload_filters` to shrink the entity set before parallelizing.
3. Set `execution_timeout_hours` on long fan-out tables (OiTchau hours bank uses `5`).
4. Keep `max_workers` at or below the HTTP connection pool size used by `BaseAPIClient` (default `pool_maxsize=64`) so workers reuse keep-alive TLS connections.
5. Migrating the DAG to EMR (cluster YAML) is independent of enabling `max_workers`; both are required for production People runs on EMR.

```yaml
id_expansion:
  source_table: employees
  id_field: uuid
  param_name: employeeUuid
  max_workers: 64
  payload_filters:
    - field: active
      equals: true
```

### `date_expansion` (per-table, optional)

When an endpoint bounds how much time one call may cover, use table-level **`date_expansion`** to repeat the fetch for multiple dates. It works in two shapes:

- **With `id_expansion`** (e.g. Oitchau `employees/hoursbank/totals?date=`): tasks become **entity × date**.
- **Without `id_expansion`** (plain table, e.g. Oitchau `punches?from=&to=`): the job performs **one fetch per expanded date** (each with the table's pagination, when configured) and concatenates the results.

| Key | Required | Description |
|-----|----------|-------------|
| `param_name` | one of `param_name` / `param_names` | Query param to override per iteration (e.g. `date`) |
| `param_names` | one of `param_name` / `param_names` | List of query params **all set to the same expanded date** — for range endpoints that cap the window at one day (e.g. `[from, to]` when the API answers `400 "Date range from-to cannot be bigger than 1 day"`) |
| `strategy` | yes | `load_window` — every date from `load_start_date` through `load_end_date` inclusive; `last_n_days` — inclusive rolling window of `days` ending on the anchor; or `previous_and_current_calendar_month` — from the 1st of the previous calendar month through the anchor |
| `days` | when `strategy: last_n_days` | Positive integer (e.g. `45` for ~six weeks of retroactive hours-bank adjustments) |
| `anchor` | no | `load_end_date` (default) or `load_start_date` — last day of the window for `last_n_days` |

For `strategy: load_window`, the Spark job uses the dates already resolved from
the task arguments (including `dag_run.conf`). The range is inclusive: equal
start and end dates make one request, while a start date after the end date
fails validation with a clear error. The existing strategies are unchanged.

Keep the **clean SQL** date filter aligned with the chosen window (e.g. for `last_n_days: 45` and `anchor: load_end_date`, filter `dt_balanced` between `DATE_ADD(load_end_date, -44)` and `load_end_date` inclusive).

Under `id_expansion`, combine with `max_workers` and `payload_filters` to control volume and concurrency — without parallel workers, a large lookback window will usually exceed Airflow task timeouts. Plain (non-`id_expansion`) tables fetch the expanded dates sequentially, one paginated fetch per date.

Raw incremental loads **append**: every run re-appends the overlapping window, so pair the lookback with a `merge_on` key and a latest-`ts_load` dedup in the clean query (see the punches example).

### Explicit load windows, date offsets, and availability tolerance

Date placeholders in `tables_customization.<table>.params` may include a
signed integer day offset:

```yaml
tables_customization:
  summaries:
    endpoint_path: summaries
    params:
      starting_date: load_start_date
      ending_date: load_end_date+1
    availability_tolerance:
      message_patterns:
        - "latest available data"
```

Offsets are applied by the Spark job **after** the `load_start_date` and
`load_end_date` arguments have been resolved. Therefore, a run supplied with
`dag_run.conf` uses the conf dates and then applies `+N` or `-N`; Jinja-only
offsets are not required for this behavior. Exact placeholders and literal
parameter values remain unchanged. Supported forms are
`load_start_date`, `load_start_date±N`, `load_end_date`, and
`load_end_date±N`, where `N` is an integer number of calendar days. Malformed
forms fail with an actionable configuration error.

`availability_tolerance` is opt-in and accepts a non-empty list of
case-insensitive regular-expression `message_patterns`. A matching response
is tolerated only when its status is **400**; the affected request/date is
logged as a warning and skipped. If the request used an offset placeholder,
the job retries once with the equivalent unshifted date before warning and
skipping. A second matching unavailable-date response is skipped; a
non-matching response still fails after the client's existing retries.
Without `availability_tolerance`, `id_expansion` retains its existing
per-entity error handling.

Do not use availability tolerance to hide usage/cost range-limit errors:
those vendor endpoints remain capped at **31 days**, and this framework does
not chunk or tolerate that limit.

### Runtime behaviour

1. Spark reads `datalake_{custom_schema}_raw.{source_table}` and extracts distinct non-null `id_field` values from the `payload` JSON column.
2. For each entity ID, the job either:
   - substitutes **`{path_param}`** inside `endpoint_path` with the entity id (no query param for the id itself), or
   - adds **`param_name=<entity_id>`** to the request query string (merged with `params`), or
   - sends **`POST`** with JSON body **`{ "<json_body_field>": "<entity_id>" }`** (query `params` from the table config are still sent on the URL when set).
3. If the table declares **`api_policies.pagination`** (e.g. **`page_per_page`**), each per-entity call uses that paginator and all pages are flattened into rows; otherwise a single GET is performed. If the response looks paginated (e.g. `metadata.totalPages` > 1) but no paginator is configured, only the first page is fetched and a **warning** is logged.
4. Each row is stamped with **`correlation_field`** if set, else **`id_field`**, set to the fan-out entity id (so list items keep API-native keys such as `uuid` when needed).
5. Failed individual calls (HTTP errors, timeouts) are logged as warnings and skipped — the job continues with the remaining IDs.
6. All collected records are written to the raw layer as a single Delta table write.

### Example — OiTchau hours bank balance

```yaml
tables_customization:
  hoursbank_totals:
    endpoint_path: employees/hoursbank/totals
    extraction_type: incremental
    execution_timeout_hours: 5
    date_expansion:
      param_name: date
      strategy: last_n_days
      days: 45
      anchor: load_end_date
    id_expansion:
      source_table: employees
      id_field: uuid
      param_name: employeeUuid
      max_workers: 64
      payload_filters:
        - field: active
          equals: true
    date_format: "%Y-%m-%d"
    date_filter_column: date
    params:
      date: load_start_date
    vacuum_retention_hours: 168
    vacuum_lite: true
```

This fetches hours-bank balances for each **active** employee UUID for each of the last **45 days** through `load_end_date` (one API call per employee per day), with up to 32 parallel HTTP workers on the Spark driver.

### Example — daily range endpoint without id_expansion (OiTchau `punches`)

The punches API takes `from`/`to` but rejects ranges wider than one day, and
retroactive punch adjustments (`is_manual_adjustment`) land on past dates —
so the lookback is one paginated call per day with both params pinned to the
expanded date:

```yaml
tables_customization:
  punches:
    endpoint_path: punches
    extraction_type: incremental
    date_format: "%Y-%m-%d"
    date_filter_column: date
    date_expansion:
      param_names: [from, to]
      strategy: last_n_days
      days: 45
      anchor: load_end_date
    params: {}
    api_policies:
      pagination:
        strategy: page_per_page
        page_param: page
        per_page_param: per_page
        page_size: 100
    merge_on:
      - id_punch
```

Keep the **clean SQL** read window aligned (e.g. `MAKE_DATE(year, month, day)
BETWEEN DATE_ADD(load_end_date, -44) AND load_end_date` when `anchor:
load_end_date` and `days: 45`) so re-fetched old punch-date partitions flow
through, and dedup per `id_punch` by latest `ts_load` before the merge.

### Example — POST JSON body fan-out (OiTchau `costs/list`)

```yaml
tables_customization:
  employee_costs:
    endpoint_path: costs/list
    extraction_type: full
    params: {}
    id_expansion:
      source_table: employees
      id_field: externalId
      correlation_field: employeeExternalId
      json_body_field: employeeExternalId
    merge_on:
      - id_cost_segment
```

Chain after `employees` via `workflow.raw_inner_dependencies.employee_costs: [employees]`. Each row in `content[]` becomes one raw record; `correlation_field` stamps the request identifier for joins.

### Example — path param + pagination (OiTchau requests per employee)

```yaml
tables_customization:
  requests_employees:
    endpoint_path: requests/employees/{employeeUuid}
    extraction_type: incremental
    id_expansion:
      source_table: employees
      id_field: uuid
      path_param: employeeUuid
    date_format: "%Y-%m-%d"
    params:
      from: load_start_date
      to: load_end_date
    api_policies:
      pagination:
        strategy: page_per_page
        page_param: page
        per_page_param: per_page
        page_size: 100
```

### Limitations

- **`path_param`**: `endpoint_path` must contain the placeholder **`{<path_param>}`** exactly as built by the job (e.g. `{employeeUuid}`). Typos or missing braces fail at runtime.
- **Unsupported fan-out patterns** still need a custom Spark job (e.g. multiple different path placeholders per call, or IDs not present in a prior raw table in the same DAG).
- The `source_table` must be ingested by the same DAG and exist in the raw layer before the `id_expansion` table task runs. Use **`workflow.raw_inner_dependencies`** (or **`inner_dependencies`**) so the source raw task finishes first.

---

## Authentication (`workflow.authentication`)

> **Runtime:** New `api_ingestion` DAGs run on EMR. When `SPARK_RUNTIME=emr`, the shared
> runtime resolves credentials from **AWS Secrets Manager** using the EMR instance role. Secrets
> are mirrored from Vault; EMR does not read Vault directly. Before implementing a new
> ingestion, see [prerequisites.md](prerequisites.md) for the mirror request. Databricks
> Secrets remains a legacy path for existing Databricks runs.

On EMR:

- `authentication.secret_key` is the AWS Secrets Manager secret ID by default.
- `workflow.credentials_scope` remains available as a compatibility input when an
  `BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE` uses `{scope}`.

Whenever the API requires a credential (API key, token, client secret, etc.), it **must be
stored in Vault and mirrored to AWS Secrets Manager** using the process in
[prerequisites.md](prerequisites.md). Never create or rotate the EMR secret directly in the
AWS or Databricks UI.

For legacy Databricks runs, the key is read from the scope configured by
`workflow.credentials_scope`, or `DATABRICKS_SECRET_SCOPE` (default: `quintoandar`). See
[Save a credential in Databricks Secrets](https://docs.google.com/document/d/1ZqeBdDOoij00-0lYF1QbWkmQdKFBVg494wlQTTHuLFY/edit?tab=t.0#heading=h.yvxztbuje7xm)
only for that legacy path.

### `strategy: none`

No auth is applied.

### `strategy: basic`

Adds `Authorization: Basic <token>` to all requests.

Config:

- **secret_key** (string, required)
- **token_field** (string, optional, default: `api_token`)
- **username_field / password_field** (optional): if both are set, the token is built from `username:password` and base64-encoded

### `strategy: oauth2_client_credentials`

Fetches a token from `token_url` using **Basic Auth** (client_id/client_secret stored in Secrets) and then sends requests with `Authorization: Bearer <access_token>`.

Config:

- **secret_key** (string, required)
- **token_url** (string, required)
- **client_id_field** (string, optional, default: `client_id`)
- **client_secret_field** (string, optional, default: `client_secret`)
- **token_payload_extras** (dict, optional): extra payload fields added to the token request (`grant_type=client_credentials` is always included)
- **expires_at_field / expires_in_field** (optional): how to read expiration from token response (defaults: `expires_at` / `expires_in`)

### Parameter reference (authentication)

- **`authentication.strategy`** string (required): one of `none`, `basic`, `oauth2_client_credentials`, `api_key`.
- **`authentication.secret_key`** string (required for `basic`, `oauth2_client_credentials`, and `api_key`): secret ID/key.
  - On EMR, this is the AWS Secrets Manager secret ID unless the configured
    `BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE` changes the mapping.
  - On legacy Databricks runs, it is the key inside the scope from
    `workflow.credentials_scope` or `DATABRICKS_SECRET_SCOPE` (default: `quintoandar`).

For **`strategy: basic`**:

- **`authentication.token_field`** string (optional, default: `api_token`): field in secret JSON holding the (pre-encoded) token.
- **`authentication.username_field`** string (optional): if set together with `password_field`, builds token from `username:password`.
- **`authentication.password_field`** string (optional): see above.
- A raw secret string is also accepted when username/password fields are not configured; it is encoded as `<raw_token>:` for the Basic Auth header.

For **`strategy: oauth2_client_credentials`**:

- **`authentication.token_url`** string (required): token endpoint URL.
- **`authentication.client_id_field`** string (optional, default: `client_id`): field in secret JSON.
- **`authentication.client_secret_field`** string (optional, default: `client_secret`): field in secret JSON.
- **`authentication.token_payload_extras`** dict (optional, default: `{}`): merged into the token request. With the default **`token_request_format`** (`form_basic_auth`), extras are sent as **form** fields together with `grant_type=client_credentials` and HTTP Basic Auth (client id/secret). With **`token_request_format: json_body`**, extras are merged into a **JSON** body that also includes `client_id`, `client_secret`, and `grant_type`.
- **`authentication.token_request_format`** string (optional, default: `form_basic_auth`): `form_basic_auth` (form body + HTTP Basic Auth to the token URL) or `json_body` (JSON body, no HTTP Basic Auth on the token call).
- **`authentication.access_token_field`** string (optional, default: `access_token`): name of the access token property in the token JSON response (some APIs use camelCase, e.g. `accessToken`).
- **`authentication.expires_at_field`** string (optional, default: `expires_at`): absolute expiry field in token response.
- **`authentication.expires_in_field`** string (optional, default: `expires_in`): relative expiry field in token response.

**Workflow-level (not under `authentication`):** **`http_user_agent`** applies to the HTTP session for API calls and, when using OAuth2, to token requests as well. **`http_headers`** are session-level static headers for API calls only (not OAuth token requests). See the workflow parameter reference.

For **`strategy: api_key`**:

- **`authentication.secret_key`** string (required): secret ID/key containing
  the API key; lookup uses the active runtime's secret backend described above.
- **`authentication.api_key_field`** string (optional, default: `api_key`): field in secret JSON holding the API key value.
- **`authentication.location`** string (optional, default: `header`): one of `header`, `query_param`.
- **`authentication.header_name`** string (optional, default: `x-api-key`): header name when using `location: header`.
- **`authentication.query_param_name`** string (optional, default: `token`): query param name when using `location: query_param`.

---

## Bounded validation on EMR

Framework changes can be validated before a downstream DAG adopts them by
running the branch Spark job in an ephemeral EMR step.

- Stage the branch job and a temporary validation driver through the approved
  EMR artifact path; confirm the artifact source SHA before execution.
- Run with `SPARK_RUNTIME=emr` and the existing Vault → AWS Secrets Manager
  mirror. Do not place credentials in the runner, command arguments, or logs.
- Use a bounded three-day `dag_run.conf` window and an in-memory configuration
  overlay to exercise date expansion, post-conf offsets, and availability
  fallback without changing the production declaration.
- Replace the raw writer with an aggregate-only collector. Evidence may include
  request dates, counts, statuses, fallback counts, runtime, and source SHA,
  but must not include API payloads or write production raw tables.
- Terminate the ephemeral EMR cluster through the approved lifecycle after the
  result is collected.

This bounded run validates the shared framework only. End-to-end behavior after
`claude_usage_api` adopts the options is a separate follow-up validation.

---

## Request params and date placeholders

When you set `params` for a table, the job replaces:

- `load_start_date` with:
  - `date_format_mask` / `date_format` if configured, otherwise ISO-8601 with `T00:00:00.000Z`
- `load_end_date` with:
  - `date_format_mask` / `date_format` if configured, otherwise ISO-8601 with `T23:59:59.999Z`

If the **`params` key is omitted** for a table, the job defaults to:

- `after_time=<start>`
- `before_time=<end>`

If the table sets **`params: {}` explicitly**, **no** query parameters are added (use this for endpoints that do not support date filters).

### Runtime params and `extra_details`

`load_api_ingestion_raw` does **not** take an `extra_details` argument and **does not** merge Airflow-provided param overrides. Query parameters come from the DAG declaration (`tables_customization.<table>.params`) and from `load_start_date` / `load_end_date` passed as Spark job arguments 7–8.

Those dates are resolved by `LoadAPIRawTaskCreator` from `extra_query_template_params`:

1. `tables_customization.<table>.extra_query_template_params` if present (replaces the workflow dict).
2. Else `workflow.extra_query_template_params`.
3. Missing `load_start_date` / `load_end_date` are filled from the DAG execution context.

To change the window for one table without shifting the rest of the DAG, set table-level `extra_query_template_params` (see the per-table parameter reference). To change params for a run, use declaration config / macros, or extend the job (see [`contributing.md`](contributing.md)).

---

## Pagination (`api_policies.pagination`)

Pagination can be configured at workflow level and overridden per-table.

Supported strategies:

- `none`
- `offset_limit`
- `page_per_page` (1-based `page` / `per_page` query params; optional **`results_response_path`**)
- `cursor` (Point-In-Time **or** query-param cursor; location is configurable)

### `strategy: offset_limit`

Config:

- **limit_param** (default: `limit`)
- **offset_param** (default: `offset`)
- **page_size** (default: `100`)

The paginator will:

- request pages with `offset=0, page_size`
- increment offset by `page_size` until the response returns fewer than `page_size` records (or empty)

### `strategy: cursor`

This implementation covers Point-In-Time “search_after” APIs (Greenhouse Audit Log style) and standard query-param cursors.

Config (defaults shown — PIT / header-based):

- **cursor_param**: `Search-After`
- **cursor_location**: `header` (`header` or `param`)
- **cursor_response_path**: `paging.next_search_after` (read from response JSON)
- **context_param**: `Pit-Id`
- **context_location**: `header` (`header` or `param`)
- **context_response_path**: `paging.pit_id` (read from response JSON)
- **page_size_param**: `Size`
- **page_size_location**: `header` (`header` or `param`)
- **page_size**: `500`
- **results_response_path** (string, optional): field name in the response JSON containing the paginated results array. If not specified, the paginator automatically tries common field names (`results`, `items`, `data`, `records`, `entries`).

Important behavior:

- Cursor, context, and page size are sent via **headers** unless the matching `*_location` key is set to `param`.
- Pagination stops when the results list is empty or `cursor_response_path` is empty (no extra `has_more` hook).
- If `results_response_path` is not specified, results are automatically extracted from common field names (`results`, `items`, `data`, `records`, `entries`). If specified, only that field is used.

Query-param example (`next_page` in the JSON body becomes `?page=` on the next request):

```yaml
api_policies:
  pagination:
    strategy: "cursor"
    cursor_location: "param"
    cursor_param: "page"
    cursor_response_path: "next_page"
```

### `strategy: page_per_page`

For APIs that use **1-based page index** and **page size** as query parameters (common pattern: `page`, `per_page`), with optional **`metadata`** in the JSON body to signal the last page (`page` / `totalPages`, including snake_case variants).

Config (defaults shown):

- **page_param** (default: `page`)
- **per_page_param** (default: `per_page`)
- **page_size** (default: `100`)
- **results_response_path** (string, optional): if set, the paginator reads only that key for the list of rows; if omitted, **`PagePerPagePaginator`** tries common list keys (`results`, `items`, `data`, `content`, `records`, `entries`).

Stopping rules:

- current page **≥** `metadata.totalPages` (when both are present and parseable), or
- the page returns **fewer rows than `page_size`**, or
- the page is **empty**.

**`delay_seconds`** from **`api_policies.rate_limiting`** (workflow or table) is applied as **`page_delay`** between pages for this paginator.

---

## Rate limiting (`api_policies.rate_limiting`)

Supported strategies:

- `none`
- `fixed_delay`

### `strategy: fixed_delay`

- **delay_seconds** (float): sleep time between pages when pagination is enabled.
- **initial_delay_seconds** (int, optional): seconds to sleep **before the first request** for the table (handled in `load_api_ingestion_raw` before the client is used).
- **retry_after_header** (string, optional): allowed in the declaration schema for forward compatibility; the shared `HeaderRateLimitAdapter` currently reads the standard **`Retry-After`** header only (custom header names are not wired through from YAML yet).

Notes:

- **`delay_seconds`** is applied **between pages**, not between independent tables.
- Retries use urllib3’s `Retry` inside `BaseAPIClient` with a fixed `backoff_factor` and default status list (`429`, `500`, `502`, `503`, `504`); YAML `retry_policy.delay` / `backoff_factor` do not change that adapter today.

---

## Error handling (`api_policies.error_handling`)

### Retries (`retry_policy`)

- **`retries`**: mapped to `BaseAPIClient(..., max_retries=...)` (urllib3 `Retry.total`).
- **`delay`**, **`backoff_factor`**, **`status_forcelist`**: preserved in YAML and surfaced in loader logs only; they do **not** currently reconfigure the urllib3 `Retry` object (see `bietlejuice/base/api/common/client.py`).

### Non-fatal errors (`non_fatal_status_codes`)

Declared for future behavior. Today the loader **logs** the list during client creation; **`BaseAPIClient` does not treat these codes as non-fatal** — the job still fails on HTTP error after the standard retry path unless the response is successful.

---

## YAML examples (supported features)

The snippets below are intended to be copy/paste starting points for new DAGs and for validating supported strategies.

### Minimal `api_ingestion` DAG (no auth, no pagination)

```yaml
workflow:
  layer: raw
  type: api_ingestion
  api_base_url: "https://api.example.com/v1"

  authentication:
    strategy: "none"

  api_policies:
    pagination:
      strategy: "none"
    rate_limiting:
      strategy: "none"

  tables_customization:
    my_table:
      endpoint_path: "events"
```

### `api_base_url` per environment

```yaml
workflow:
  api_base_url:
    forno: "https://sandbox.api.example.com/v1"
    prod: "https://api.example.com/v1"
```

### Auth: Basic (token from Secrets)

```yaml
workflow:
  authentication:
    strategy: "basic"
    secret_key: "MY_API_SECRET"
    token_field: "token"
```

### Auth: Basic (username/password from Secrets)

```yaml
workflow:
  authentication:
    strategy: "basic"
    secret_key: "MY_API_SECRET"
    username_field: "username"
    password_field: "password"
```

### Auth: OAuth2 Client Credentials (token endpoint protected by Basic Auth)

```yaml
workflow:
  authentication:
    strategy: "oauth2_client_credentials"
    secret_key: "MY_OAUTH_SECRET"
    token_url: "https://auth.example.com/oauth/token"
    client_id_field: "client_id"          # default
    client_secret_field: "client_secret"  # default
    token_payload_extras:
      audience: "https://api.example.com/"
```

### Auth: API Key (header or query parameter)

```yaml
workflow:
  authentication:
    strategy: "api_key"
    secret_key: "MY_API_KEY_SECRET"
    api_key_field: "api_key"
    location: "header"
    header_name: "x-api-key"
    # query_param_name: "token"
```

### Params with date placeholders + ISO timestamps (default)

```yaml
workflow:
  tables_customization:
    events:
      endpoint_path: "events"
      params:
        after_time: "load_start_date"
        before_time: "load_end_date"
```

### Params with custom date formatting (workflow-level)

```yaml
workflow:
  date_format_mask: "%Y%m%d"
  tables_customization:
    rates:
      endpoint_path: "USD-BRL/360"
      params:
        start_date: "load_start_date"
        end_date: "load_end_date"
```

### Date formatting override (table-level)

```yaml
workflow:
  date_format_mask: "%Y%m%d"
  tables_customization:
    events:
      endpoint_path: "events"
      date_format: "%Y-%m-%d"
      params:
        start: "load_start_date"
        end: "load_end_date"
```

### Pagination: offset/limit

```yaml
workflow:
  api_policies:
    pagination:
      strategy: "offset_limit"
      limit_param: "limit"
      offset_param: "offset"
      page_size: 100
```

### Pagination: cursor (PIT + search_after header-based)

```yaml
workflow:
  api_policies:
    pagination:
      strategy: "cursor"
      cursor_param: "Search-After"
      cursor_response_path: "paging.next_search_after"
      context_param: "Pit-Id"
      context_response_path: "paging.pit_id"
      page_size_param: "Size"
      page_size: 500
      results_response_path: "results"  # optional: defaults to trying common field names
```

### Pagination: page / per_page (table override)

```yaml
workflow:
  api_policies:
    pagination:
      strategy: "none"
    rate_limiting:
      strategy: "none"
  tables_customization:
    events:
      endpoint_path: "events"
      api_policies:
        pagination:
          strategy: "page_per_page"
          page_param: "page"
          per_page_param: "per_page"
          page_size: 100
```

### Rate limiting: fixed delay between pages

```yaml
workflow:
  api_policies:
    rate_limiting:
      strategy: "fixed_delay"
      delay_seconds: 1.0
      retry_after_header: "Retry-After"
```

### Error handling: retry policy + non-fatal codes

```yaml
workflow:
  api_policies:
    error_handling:
      non_fatal_status_codes: [500]
      retry_policy:
        retries: 3
        delay: 2
        backoff_factor: 2
```

### Per-table override (auth/pagination/error handling)

```yaml
workflow:
  authentication:
    strategy: "none"
  api_policies:
    pagination:
      strategy: "none"

  tables_customization:
    public_events:
      endpoint_path: "events"

    private_events:
      endpoint_path: "private/events"
      authentication:
        strategy: "basic"
        secret_key: "PRIVATE_API_SECRET"
      api_policies:
        pagination:
          strategy: "offset_limit"
          limit_param: "limit"
          offset_param: "offset"
          page_size: 50
        error_handling:
          retry_policy:
            retries: 5
            delay: 3
            backoff_factor: 2
```

### Serializing raw tables (avoid concurrency issues)

Some APIs can return intermittent 401s (or other failures) if multiple tables hit the API in parallel (e.g., token invalidation races). You can serialize raw loads with `raw_inner_dependencies` (or `inner_dependencies`):

```yaml
workflow:
  raw_inner_dependencies:
    job_interview_stages:
      - application_stages
    users:
      - job_interview_stages
```

### Payload column name + partitioning by a JSON date field

```yaml
workflow:
  payload_column_name: "raw_payload"
  tables_customization:
    events:
      endpoint_path: "events"
      date_filter_column: "event_time"
```

---

## Output: raw table schema

The Spark job builds rows with `bietlejuice.jobs.common.helpers.json_to_dataframe`:

- API objects are passed through `clean_keys_recursive` (keys sanitized for Spark-friendly names).
- When **`payload_column_name`** is set (default `payload`), each row includes that column with **`json.dumps(original_record)`** so the full response object is retained as a JSON string.
- Spark infers additional columns from the normalized dicts (when the API returns flat fields, they appear as their own columns in addition to the payload column, depending on inference across the batch).
- **`insert_partitions`** then adds **`ts_load`** (`now()`), and **`year`**, **`month`**, **`day`**. If **`date_filter_column`** is set (table or workflow), partitions are derived from that field when possible; otherwise partitions use the load timestamp.

There is **no** dedicated `source` URL column written by `load_api_ingestion_raw` today (only the raw payload and inferred fields).

---

## Reference DAGs

- [`dags/people/oitchau_api/oitchau_api_declaration.yml`](../../dags/people/oitchau_api/oitchau_api_declaration.yml) — `api_ingestion` reference: **`token_request_format: json_body`** OAuth2, optional **`http_user_agent`**, **`credentials_scope`**, tables with **`params: {}`** where the API rejects default date filters, **`page_per_page`** on large list endpoints, **`id_expansion`** with **`param_name`** (hours bank), **`path_param`** + **`page_per_page`** (per-employee requests), **`json_body_field`** + **`correlation_field`** for **POST** `costs/list`, **`workflow.raw_inner_dependencies`** for fan-out after `employees`, plus **clean** tables in the same DAG package (`queries/clean/*.sql`, **`merge_on`**, **`default_clean_extraction_type`** / **`default_clean_partitions`**).

---

## Known limitations (current MVP)

### Authentication

- Supported strategies: `oauth2_client_credentials`, `basic`, `api_key`, and `none`.
- No Service Account / JWT flows (e.g., Google Workspace service account) are implemented.
- No generic Bearer token strategy (static token from Secrets) is implemented.

### Parallelism and token invalidation (401)

Some APIs can invalidate previously-issued tokens when a new token is generated (or have other concurrency-sensitive auth behavior). Because `api_ingestion` can run multiple tables in parallel, this can surface as intermittent `401 Unauthorized` for some endpoints.

- Example: Greenhouse v3 had intermittent 401s during parallel ingestions; one mitigation was to serialize raw loads using intra-DAG dependencies (see [PR #21643](https://github.com/quintoandar/bi-etl-ejuice/pull/21643)).

**Workaround:** serialize the affected tables using `workflow.raw_inner_dependencies` (or `workflow.inner_dependencies`) (do **not** provide empty lists; only include tables that have dependencies):

```yaml
workflow:
  raw_inner_dependencies:
    job_interview_stages:
      - application_stages
    users:
      - job_interview_stages
```

Longer-term, shared/reused token handling across parallel tasks is not implemented in the current MVP.

### Pagination

- No `link_header` pagination strategy.
- **`_create_cursor_paginator`** reads **`cursor_location` / `context_location` / `page_size_location`** from pagination YAML (`header` or `param`). The default is **`header`** so existing PIT configs stay unchanged.
- For **cursor** pagination, result lists are resolved with **`CursorPaginator._default_extract_results`**, which scans `results`, `items`, `data`, `records`, `entries` (or a configured `results_response_path`).
- **`page_per_page`** uses body **`metadata`** (`totalPages` / `page`, including snake_case) when present; otherwise it stops on short/empty pages (see [`PagePerPagePaginator`](../../bietlejuice/base/api/pagination/page_per_page.py)).
- For a **single-page** fetch (no paginator), `load_api_ingestion_raw` reads **`table_config.results_response_path`** (default key name **`"results"`**), then falls back to **`data`** if the list is empty — it does **not** scan all common names like the cursor paginator.

### Rate limiting / 429

- **`fixed_delay` / `delay_seconds`** only sleep **between pages** (when a paginator is used).
- **`initial_delay_seconds`** sleeps once before any HTTP traffic for the table.
- After a 429, urllib3 retries with the adapter stack; **`HeaderRateLimitAdapter`** may wait on the **`Retry-After`** response header. YAML **`retry_after_header`** is not passed through to rename that header yet.

### Response extraction

- **Single request:** default **`results`** key (override with per-table **`results_response_path`**), then **`data`** if empty; if the body is a **list**, it is used as-is.
- **Cursor pagination:** default extractor tries common keys unless **`results_response_path`** is set in pagination config (see [`CursorPaginator`](../../bietlejuice/base/api/pagination/cursor.py)).

---

## Contributing

If you want to extend `api_ingestion` (new auth/pagination/rate-limit strategies), see:

- [`docs/api_ingestion/contributing.md`](contributing.md)

