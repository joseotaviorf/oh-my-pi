# Contributing Guide — `api_ingestion` workflow

This document is a reference for contributors who want to evolve the **api_ingestion** workflow (DAG Builder + API runtime + Spark job).

It focuses on **where** to implement changes, **which files** to touch, and **which tests** to add.

If you want to learn **how to use** the workflow to ingest new endpoints/tables into the lake, read:

- [API Ingestion](user_guide.md)

---

## Background: why this exists

The `api_ingestion` workflow builds on top of the reusable components in [`bietlejuice/base/api/`](../../bietlejuice/base/api/).
The goal is to reduce common pain points when integrating REST APIs:

- **Code duplication**: auth/pagination/error-handling being re-implemented per DAG/job
- **Inconsistency**: divergent patterns across pipelines, harder maintenance
- **Lack of robustness**: missing retries/rate limits/standard error behavior

When contributing, prefer changes that improve **reusability** and **config-driven behavior** across many APIs.

### Packaging: `dag_name` vs `custom_schema`

New **`api_ingestion`** DAGs must use a **`dag.name`** (folder + `{dag_name}_declaration.yml`) ending in **`_api`** so the file matches [`MANIFEST.in`](../../MANIFEST.in) (`*_api_declaration.y*ml`) and is bundled in the wheel for Databricks. **`workflow.custom_schema`** and raw metastore schema names **do not** follow that suffix rule — see [`user_guide.md`](user_guide.md) (*API ingestion DAG naming and schema*).

---

## Architecture (what runs where)

### **DAG Builder**

- **Workflow orchestration** (creates tasks, dependencies):  
  [`bietlejuice/base/airflow/dag_builders/main_builder/workflows/raw_api_ingestion_workflow.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/workflows/raw_api_ingestion_workflow.py)
  - Responsible for turning the YAML declaration into an Airflow DAG structure (tasks + dependencies).
  - Decides which tasks exist for each table (load raw, optional clean, DQ, sync metadata, optimize).
  - Defines default Spark job settings for `api_ingestion` (job name, prefix, arguments).

- **YAML validation rules (Cerberus + extra validation)**:  
  [`bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py)
  - Responsible for failing fast during DAG parsing when YAML is invalid/missing required keys.
  - Enforces `api_ingestion`-specific requirements (e.g., `api_base_url`, `authentication`, `endpoint_path`).

- **Accepted values (enums)** used by validation/runtime:  
  [`bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py)
  - Source of truth for supported `authentication`, `pagination`, and `rate_limiting` strategy names.
  - Should be updated whenever you add/remove a supported strategy.

- **Building the API raw Spark task** (fixed positional args, no `extra_details`):  
  [`bietlejuice/base/airflow/task_creators/load_api_raw_task_creator.py`](../../bietlejuice/base/airflow/task_creators/load_api_raw_task_creator.py)
  - Implements `LoadAPIRawTaskCreator`, which calls `load_api_ingestion_raw` with: environment, bucket, dag name, table name, execution date, partitions JSON, extraction type, `load_start_date`, `load_end_date`.
  - Request query params are **not** passed from Airflow as `extra_details`; the Spark job reloads the DAG declaration and `APIConfigurationLoader.get_initial_params()` derives params from YAML plus those dates.

### **API runtime**

- **Reusable Spark job entrypoint** (what the DAG actually runs):  
  [`dags/cross/base/spark_jobs/load_api_ingestion_raw.py`](../../dags/cross/base/spark_jobs/load_api_ingestion_raw.py)
  - Responsible for reading the DAG declaration, selecting the table config, building the request, fetching pages, and writing raw output.
  - Orchestrates the runtime flow (loader → client/paginator → fetch → DataFrame → RawLayerLoader).

- **YAML → runtime objects** (client, auth, paginator, policies):  
  [`bietlejuice/base/api/configuration/loader.py`](../../bietlejuice/base/api/configuration/loader.py)
  - Responsible for interpreting YAML config and instantiating executable components:
    - `BaseAPIClient` (retry policy, non-fatal codes, alerts)
    - authentication handler(s)
    - paginator (cursor / offset_limit / none)
  - If you add new knobs or strategies, the loader is usually the central wiring point.

- **HTTP client + retries + alerts**:  
  [`bietlejuice/base/api/common/client.py`](../../bietlejuice/base/api/common/client.py)
  - Responsible for request execution, URL composition, urllib3 retries, and standardized HTTP error handling.
  - Implements alerting behavior (`alert_channel`) and “non-fatal” HTTP codes logic.

- **Authentication strategies**:  
  [`bietlejuice/base/api/auth/`](../../bietlejuice/base/api/auth/)
  - Responsible for applying request authentication (headers/session auth) using secrets from Databricks.

- **Pagination strategies**:  
  [`bietlejuice/base/api/pagination/`](../../bietlejuice/base/api/pagination/)
  - Responsible for iterating through pages and yielding records per page according to the API pagination scheme.

- **Rate-limit adapter** (header-based waiting + retries integration):  
  [`bietlejuice/base/api/rate_limit/header_adapter.py`](../../bietlejuice/base/api/rate_limit/header_adapter.py)
  - Responsible for session-level, header-driven rate-limit behavior (e.g., reacting to common rate limit headers).

---

## Adding a new authentication strategy (example)

This section uses **authentication** as the main example, but the same contribution pattern applies to other extensions (new pagination strategies, rate limiting behaviors, response extraction knobs, etc.): implement the component, wire it in the loader/enums, validate YAML, add tests, and document it.

### 1) Add the implementation

Create a new auth handler in [`bietlejuice/base/api/auth/`](../../bietlejuice/base/api/auth/).

Guidelines:

- Extend `AuthBase` ([`bietlejuice/base/api/auth/base.py`](../../bietlejuice/base/api/auth/base.py)) and, if you want to plug into `requests.Session.auth`, also extend `requests.auth.AuthBase`.
- Fetch secrets via `AuthBase._get_secrets_from_dbutils()` (Databricks Secrets).
- Implement `__call__(self, r: PreparedRequest)` to add headers.
- Provide `apply_auth(self, session)` to configure the session.

Example targets:

- **Bearer token** from Secrets (static token) - not yet implemented
- **Google Service Account JWT** (Workspace-style), using `Authorization: Bearer <access_token>` with token minted from a service account - not yet implemented

Note: **API Key** authentication (header or query param) is already implemented. See [`bietlejuice/base/api/auth/api_key.py`](../../bietlejuice/base/api/auth/api_key.py) for reference.

### 2) Expose the new strategy in enums

Update:

- [`bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py)
  - add a new value to `AuthenticationStrategyEnum`

### 3) Wire it in the configuration loader

Update:

- [`bietlejuice/base/api/configuration/loader.py`](../../bietlejuice/base/api/configuration/loader.py)
  - `create_api_client()` must recognize the new `authentication.strategy`
  - add a private method (pattern used today):
    - `_apply_<your_strategy>_authentication(client, auth_config)`
  - validate required config keys and raise `ValueError` with clear messages

Also check:

- default secret scope is read from `DATABRICKS_SECRET_SCOPE` (fallback `quintoandar`), but prefer setting `workflow.credentials_scope` in the DAG declaration (e.g. People domain uses `people`).

### 4) Update DAG declaration validation

At minimum, validation must allow the new strategy value:

- [`bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py)
  - ensure the workflow schema / checks accept the new enum value

If your auth requires additional YAML keys (recommended), add validations so errors appear during DAG parsing, not only at runtime.

### 5) Add/adjust unit tests

Add tests in:

- [`tests/unit/base/api/configuration/test_loader.py`](../../tests/unit/base/api/configuration/test_loader.py)  
  - loader wires the new strategy
  - required key validation is enforced
- OAuth2 variants (JSON token body, camelCase token fields): [`tests/unit/base/api/auth/test_oauth2_json_body.py`](../../tests/unit/base/api/auth/test_oauth2_json_body.py)
- Add a new file like `test_<your_auth>.py` under [`tests/unit/base/api/`](../../tests/unit/base/api/) (or extend existing auth tests)

### 6) Update docs

- Update workflow docs: [`docs/api_ingestion/user_guide.md`](user_guide.md)
- Add/update YAML examples for the new strategy in:
  - [`docs/api_ingestion/user_guide.md`](user_guide.md)

---

## Adding a new pagination strategy

### 1) Create paginator implementation

Add a new paginator under:

- Create `/<strategy>.py` under [`bietlejuice/base/api/pagination/`](../../bietlejuice/base/api/pagination/)

Keep the same interface pattern:

- inherit `BasePaginator`
- implement `fetch_all()` yielding `List[Dict[str, Any]]` per page

### 2) Register in enums and loader

Update:

- [`bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py) (`PaginationStrategyEnum`)
- [`bietlejuice/base/api/configuration/loader.py`](../../bietlejuice/base/api/configuration/loader.py)
  - recognize the new `pagination.strategy`
  - create a `_create_<strategy>_paginator(...)` helper

### 3) Decide what is configurable via YAML

Add YAML keys under `workflow.api_policies.pagination` (and allow override per table via `tables_customization.<table>.api_policies.pagination`).

Then update:

- [`bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py)
  - validate required pagination keys (page size, response fields, etc.)

### 4) Tests

Add tests in:

- Add a new `test_<your_paginator>.py` under [`tests/unit/base/api/`](../../tests/unit/base/api/)
- [`tests/unit/base/api/configuration/test_loader.py`](../../tests/unit/base/api/configuration/test_loader.py) (loader creates the paginator)

---

## Adding a new rate limiting strategy

Today the workflow supports:

- `api_policies.rate_limiting.strategy = fixed_delay` (sleep between pages)
- plus a session adapter that can react to rate-limit headers (see `HeaderRateLimitAdapter`)

If you add a new strategy (e.g., `header_based`, `token_bucket`, etc.):

1) Extend enums:

- `RateLimitingStrategyEnum` in [`bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py)

2) Wire it in loader:

- [`bietlejuice/base/api/configuration/loader.py`](../../bietlejuice/base/api/configuration/loader.py)  
  Decide whether it:
  - impacts paginator behavior (delay between pages), or
  - changes HTTP adapter/session configuration

3) Add tests:

- [`tests/unit/base/api/test_rate_limit.py`](../../tests/unit/base/api/test_rate_limit.py) (if applicable)
- [`tests/unit/base/api/configuration/test_loader.py`](../../tests/unit/base/api/configuration/test_loader.py)

---

## Adding new YAML parameters / changing contract

Whenever you add new YAML keys for `api_ingestion`, update **both**:

- **Runtime**: [`bietlejuice/base/api/configuration/loader.py`](../../bietlejuice/base/api/configuration/loader.py) + [`dags/cross/base/spark_jobs/load_api_ingestion_raw.py`](../../dags/cross/base/spark_jobs/load_api_ingestion_raw.py)
- **Validation**: [`bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py)

And add/adjust tests:

- [`tests/unit/base/airflow/dag_builders/main_builder/test_dag_declaration_validator.py`](../../tests/unit/base/airflow/dag_builders/main_builder/test_dag_declaration_validator.py)
- [`tests/unit/base/api/configuration/test_loader.py`](../../tests/unit/base/api/configuration/test_loader.py)

---

## Common pitfalls

### **Keep it highly parameterizable**

When contributing new features (auth, pagination, extraction, response parsing, rate limiting), prefer designs that are **config-driven** and work across many APIs:

- Add knobs in YAML (with safe defaults) instead of hard-coding field names, header names, and response paths.
- Prefer composing behavior via small, isolated components (auth handler, paginator, response extractor) over adding one-off API-specific branches.
- Keep table-level overrides possible (table config should be able to override workflow defaults).
- Always add validation for new required keys so misconfigurations fail during DAG parsing, not only at job runtime.

### **You may need to update “expected values” in tests**

Some unit tests assert **explicit expected values** (e.g., enum value lists, counts, default field names, or validation schema behavior). When you add a new strategy, new YAML knobs, or change defaults, it’s normal to also update these expectations.

Common places to adjust:

- [`tests/unit/base/airflow/dag_builders/main_builder/workflows/test_api_ingestion_enums.py`](../../tests/unit/base/airflow/dag_builders/main_builder/workflows/test_api_ingestion_enums.py) (enum values / counts)
- [`tests/unit/base/airflow/dag_builders/main_builder/test_dag_declaration_validator.py`](../../tests/unit/base/airflow/dag_builders/main_builder/test_dag_declaration_validator.py) (Cerberus schema + validation rules)
- [`tests/unit/base/api/configuration/test_loader.py`](../../tests/unit/base/api/configuration/test_loader.py) (loader defaults + wiring)

### **Reuse before you create**

Before implementing a new auth/paginator/rate-limit behavior, check if an existing component already solves the problem:

- [`bietlejuice/base/api/auth/`](../../bietlejuice/base/api/auth/)
- [`bietlejuice/base/api/pagination/`](../../bietlejuice/base/api/pagination/)
- [`bietlejuice/base/api/common/client.py`](../../bietlejuice/base/api/common/client.py) (retries / non-fatal errors / alerts)

### **Request params source**

- YAML `tables_customization.<table>.params`, merged with `load_start_date` / `load_end_date` inside `APIConfigurationLoader.get_initial_params()`.
- To support Airflow-driven overrides (similar to `extra_details` on other jobs), you would extend **`load_api_ingestion_raw`’s CLI**, **`LoadAPIRawTaskCreator._get_parameters`**, and the loader — there is **no** `extra_details` path today.

When changing param behavior, keep these aligned:

- [`dags/cross/base/spark_jobs/load_api_ingestion_raw.py`](../../dags/cross/base/spark_jobs/load_api_ingestion_raw.py)
- [`bietlejuice/base/api/configuration/loader.py`](../../bietlejuice/base/api/configuration/loader.py)
- [`bietlejuice/base/airflow/task_creators/load_api_raw_task_creator.py`](../../bietlejuice/base/airflow/task_creators/load_api_raw_task_creator.py)
- [`tests/unit/base/airflow/task_creators/test_load_api_raw_task_creator.py`](../../tests/unit/base/airflow/task_creators/test_load_api_raw_task_creator.py) (argument order contract)

---

## Local validation quick commands

- Unit tests for loader/pagination/auth:

```bash
pytest tests/unit/base/api -q
```

- Validator + workflow wiring:

```bash
pytest tests/unit/base/airflow/dag_builders/main_builder -q
pytest tests/unit/airflow/dag_builders/factories -q
```

---

## PR checklist (for contributors)

- [ ] Updated enums ([`bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/workflows/api_ingestion_enums.py)) if a new strategy/value was added
- [ ] Updated loader wiring ([`bietlejuice/base/api/configuration/loader.py`](../../bietlejuice/base/api/configuration/loader.py))
- [ ] Updated YAML validation ([`bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py`](../../bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_declaration_validator.py))
- [ ] Added/updated unit tests (loader + implementation)
- [ ] Updated docs:
  - [`docs/api_ingestion/user_guide.md`](user_guide.md)
  - this file ([`docs/api_ingestion/contributing.md`](contributing.md)) if the “where to change” map evolved
