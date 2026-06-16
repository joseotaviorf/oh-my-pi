# Cluster validation DAGs

Opt-in smoke tests on Graviton consolidation cluster presets before changing prod `cluster.type`.

## Enable

Add a `validation` block to `{dag}_cluster.yml` (merged into the declaration at compile time). Presence of `validation.cluster` opts the DAG in.

Prod `cluster:` is copied verbatim from the declaration (or kept as-is when already split). Validation is generated from the **effective prod cluster config**, not from prod preset name alone: the generator resolves the prod preset through `ConfigurationService`, applies the same `custom_configurations` deep merge used by runtime, maps topology to ARM, and emits every non-standard difference from the matched consolidation preset explicitly in `validation.cluster`.

```yaml
cluster:
  type: databricks_16_4_med_general_cluster

validation:
  cluster:
    type: consolidation_s_general_cluster
    custom_configurations:
      num_workers: 3
      node_type_id: m6g.xlarge
```

### How validation presets are chosen

1. Resolve effective prod with `merge_cluster_configuration` (same as runtime `JobClusterEngine`). Runtime config production is not changed by validation generation; the generator uses it as a read-only oracle.
2. Map worker and driver `node_type_id` to Graviton (`m5`/`m5a`/`m-fleet` → `m6g`, `r*` → `r6g`, `c*` → `c6g`; size suffix preserved).
3. **Single-node alignment:** prod single-node → validation `consolidation_*_single_node_*` only; prod multi-node → multi-node consolidation only (never flip modes).
4. **Worker-first preset match:** pick a consolidation preset whose default `node_type_id` equals the mapped worker type.
5. **Homogeneous driver/worker** (same instance size): preset must also match `driver_node_type_id`; overrides are only for non-default fields (`spark_version`, `num_workers`, etc.).
6. **Heterogeneous driver/worker:** match on worker size only; override `driver_node_type_id` when it differs from the preset default (do not copy worker overrides from driver).
7. **NVMe / Photon alignment:** prod Photon clusters keep `runtime_engine: PHOTON`; legacy instance types (`m5d`, `r5d`, …) map to Graviton `*gd` families when Photon is enabled. Explicit `*gd` overrides (`m6gd`, `r6gd`, `c6gd`) are preserved without Photon — local SSD is driven by the instance type, not `runtime_engine`. Explicit non-NVMe Graviton overrides (`m6g`, `r6g`, `c6g`) are never auto-upgraded to `*gd`, even when Photon is on.
8. Emit `validation.cluster.custom_configurations` only when effective prod differs from the validation preset defaults. Dictionary fields are diffed recursively (`spark_conf`, `spark_env_vars`, `aws_attributes`, etc.); list/scalar fields are emitted as full replacement values (`init_scripts`, `custom_tags` when list-shaped, `runtime_engine`, etc.).
9. **Preset-only fields:** if the prod preset has fields the consolidation preset does not have, emit them explicitly in `validation.cluster.custom_configurations`. Example: `custom_cluster_with_sedona` defines an extra Sedona `init_scripts` entry in `prod_conf.yml`; validation must carry that list explicitly because the consolidation preset only has the default `bi-etl-ejuice/init_script.sh`.
10. **Top-level cluster args:** declaration-level `custom_libraries`, `access_control_list`, and `databricks_conn_id` stay top-level under `validation.cluster`; they are not written into `custom_configurations`.

**Skip validation** when the fully-resolved validation cluster spec equals prod's effective spec — the validation would validate nothing. This covers prod already being the sole consolidation preset that matches the topology (e.g. prod `consolidation_m_memory_cluster` with `r6g.2xlarge` worker and driver) and any re-stated prod spec whose preset plus overlaid `custom_configurations` resolve to prod's running config (e.g. a just-promoted preset re-recommended from lagging history). The generator omits the `validation:` block entirely (`validation_resolves_to_prod_spec`, comparing `merge_cluster_configuration` of prod vs `merge_validation_cluster_args(prod, validation)`).

When validation is emitted, `validation.cluster.type` may match prod `cluster.type` when `validation.cluster` specifies distinguishing overrides (for example `custom_configurations`). It must still differ from prod when no overrides are present (enforced by `DAGDeclarationValidator`). `DAGDeclarationValidator` also rejects any `validation.cluster` whose resolved spec equals prod's effective spec, even when it carries overrides — a re-stated prod spec validates nothing.

Existing validation blocks are also checked against generator output. `validate-cluster-validation-files` fails when a validation-stage `*_cluster.yml` is missing generated effective-prod overrides, so stale blocks should be regenerated instead of relying on runtime fallback behavior.

### Prod topology normalization (Graviton 6g)

When `extract-cluster-validation-files` writes or regenerates `*_cluster.yml`, it **normalizes Databricks prod** `custom_configurations` topology (`node_type_id`, `driver_node_type_id`, nested `core_nodes` / `task_nodes`) using the same `map_instance_type_to_graviton` rules as validation preset selection (`m5a` → `m6g`, `r5d` → `r6g` without Photon; Photon or legacy `*d` types → `*gd`; explicit `*gd` overrides are kept as-is; explicit `m6g`/`r6g`/`c6g` overrides are kept as-is even with Photon). EMR clusters are left unchanged.

This keeps prod and `validation.cluster` family-consistent: validation `custom_configurations` should only carry non-topology diffs (`num_workers`, `aws_attributes`, `spark_version`, etc.) unless the matched consolidation preset genuinely differs from normalized prod sizes. Do not hand-edit validation topology keys; re-run the extractor instead.

`promote_cluster_validation_to_prod.py` applies the same normalization after promoting validation to prod.

### Generator and CI

```bash
# Regenerate under a subtree (optional SOURCE_REF when cluster: was removed from declarations)
# Skips DAGs whose on-disk *_cluster.yml already has validation: (still in validation stage).
make extract-cluster-validation-files DAG_PATH=dags/platform/ SOURCE_REF=<pre-split-git-ref>

# CI: extract --check (when cluster YAML changes) plus instance-family audit
make validate-cluster-validation-files

# Extract drift only (regen PRs touching *_cluster.yml)
make validate-cluster-validation-extract-check

# Tooling PRs (compiler scripts only): Woodpecker `validate-cluster-validation-tooling` runs unit tests + audit
make audit-cluster-instance-families
```

Keep `spark.databricks.sql.initial.catalog.namespace` Jinja on a single line in `*_cluster.yml` (no PyYAML line folding). `validate-cluster-validation-files` rejects folded `quintoandar_{{ var.value.environment }}` values.

Implementation: `packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/extract_cluster_validation_files.py` and `cluster_validation_mapping.py`.

Rules enforced by `DAGDeclarationValidator`:

- `validation.cluster.type` must start with `consolidation_`
- Must differ from prod `cluster.type` when `validation.cluster` has no distinguishing overrides; same preset is allowed with explicit override fields (for example `custom_configurations`)
- DAGs with `load_spark_job` need `validation.allow_custom_spark_job: true`

## Generated Airflow DAG

The compiler emits a second DAG: `bietlejuice.{dag_name}__validation`

- `schedule`: manual only (`null`)
- No `dependencies.yaml` dataset wiring
- Load tasks do not publish datasets (`produce_datasets=false`)
- Cluster preset from `validation.cluster`
- Airflow tag: `cluster_validation`
- Tasks use `retries=0` (fail fast; no Airflow task retries)

## Write target naming

| Prod | Validation (UC) |
| ---- | --------------- |
| `datalake_{schema}.{table}` | `cluster_validation.datalake_{schema}___{table}` |
| `dw_{schema}.{table}` | `cluster_validation.dw_{schema}___{table}` |
| `metric_{schema}.{table}` | `cluster_validation.metric_{schema}___{table}` |
| `qube_dimensions.{table}` | `cluster_validation.qube_dimensions___{table}` |
| `qube_measures.{table}` | `cluster_validation.qube_measures___{table}` |
| `qube_metrics.{table}` | `cluster_validation.qube_metrics___{table}` |

SQL reads stay on prod-qualified sources. Phase 1 does not rewrite `inner_dependencies`.

S3 path: `s3a://{datalake_bucket}/validation/cluster_validation/{prod_database}/`

## Runbook

1. Merge declaration + regenerated `*_dag.py`
2. Trigger `bietlejuice.{dag}__validation` manually (use `test_run` conf if needed)
3. Confirm rows in `cluster_validation.*___*` tables and prod tables unchanged
4. Switch prod `cluster.type` to consolidation when satisfied; remove `validation` block

### Batch trigger on production Astro

Use [`scripts/trigger_cluster_validation_dags.py`](../../scripts/trigger_cluster_validation_dags.py) to trigger many validation DAGs in parallel and stream status to the console as each run completes or fails.

**Prerequisites**

- Production Astro deployment API URL and token (create via `astro deployment token create`)
- Validation DAGs deployed to Airflow (tag `cluster_validation`)

```bash
export AIRFLOW_API_URL="https://<prod-deployment>.astronomer.run"
export AIRFLOW_AUTH_TOKEN="<deployment-api-token>"

# List selected DAGs from the repo only (no Airflow API)
uv run --project packages/bietlejuice-compiler python scripts/trigger_cluster_validation_dags.py \
  --lines fintech --list

# Preview triggers: resolves load windows via Airflow (no POST)
uv run --project packages/bietlejuice-compiler python scripts/trigger_cluster_validation_dags.py \
  --lines agents \
  --from-prod-run \
  --dry-run

# Trigger using each prod DAG's fastest successful run in the last 14 days
uv run --project packages/bietlejuice-compiler python scripts/trigger_cluster_validation_dags.py \
  --lines agents \
  --from-prod-run \
  --max-parallel 15

# Trigger a line with explicit load window
uv run --project packages/bietlejuice-compiler python scripts/trigger_cluster_validation_dags.py \
  --lines agents,fintech \
  --load-start-date 2024-01-01 \
  --load-end-date 2024-01-07 \
  --max-parallel 15

# Trigger all deployed validation DAGs except one line
uv run --project packages/bietlejuice-compiler python scripts/trigger_cluster_validation_dags.py \
  --exclude-lines tech_platform \
  --load-start-date 2024-01-01 \
  --load-end-date 2024-01-07

# Single DAG smoke test
uv run --project packages/bietlejuice-compiler python scripts/trigger_cluster_validation_dags.py \
  --dags journey_optimizer \
  --load-start-date 2024-01-01 \
  --load-end-date 2024-01-07
```

**Useful flags**

| Flag | Purpose |
|------|---------|
| `--lines` / `--exclude-lines` | Include or exclude `dags/<line>/` subtrees |
| `--dags` / `--exclude-dags` | Include or exclude short dag folder names |
| `--max-parallel` | Max validation DAG runs in flight at once; next starts when one finishes (default 15) |
| `--max-runs` | Deprecated; skip uses latest validation run state only (default 1) |
| `--force-retrigger` | Trigger again after a prior success; still resumes active runs and honors `--validation-cooldown-hours` (does not bypass the Databricks `dag_id` length skip) |
| `--validation-cooldown-hours` | Skip when a terminal validation run (`success` / `failed`) finished within this window (default 2; applies even with `--force-retrigger`; use `0` to disable) |
| `--dag-runs-lookback` | Recent dag runs to inspect per DAG for resume/skip (default 25) |
| `--poll-interval` | Base seconds between status polls; exponential backoff applies (default 30) |
| `--poll-max-interval` | Cap on poll backoff delay in seconds (default 300) |
| `--poll-jitter` | Fractional jitter on poll delays; also staggers the first poll in `[0, base±jitter]` (default 0.25; use 0 to disable) |
| `--skip-missing` / `--no-skip-missing` | Skip DAGs not yet deployed (default: skip) |
| `--require-all-deployed` | Fail fast if any selected DAG is missing from Airflow |
| `--list` | Repo discovery only; no Airflow calls or load dates |
| `--dry-run` | Query Airflow and print per-DAG load window, prod reference run, and action (`TRIGGER` / `RESUME` / `SKIP`); never triggers |
| `--from-prod-run` | Per-DAG `load_start_date` / `load_end_date` from prod DAG (mutually exclusive with explicit load dates) |
| `--prod-run-lookback-days` | Search window for fastest successful prod run (default 14) |
| `--prod-run-recency-days` | Skip when prod DAG has no success in this many days (default 7) |
| `--no-prod-run-recency-filter` | Do not skip idle prod DAGs |
| `--prod-run-lookback-limit` | Max successful prod runs fetched per DAG (default 100) |
| `--verbose` | Print running task ids while polling |

Before each new trigger, the script **unpauses** the validation DAG if it is paused in Airflow (`PATCH` with `is_paused: false`). DAGs are not re-paused after the run finishes. RESUME and SKIP paths do not change pause state.

While PRs land incrementally, keep `--skip-missing` enabled so only deployed validation DAGs are triggered. Failed runs print Airflow task logs to stderr immediately when they finish.

**`--from-prod-run` load window:** For each validation DAG, the script reads the matching prod DAG (`bietlejuice.{name}`, without `__validation`). Among successful prod runs in the last `--prod-run-lookback-days` (default 14) with wall-clock duration of at least **8 minutes**, it picks the run with the shortest duration (ties: most recent `start_date`). Very short prod runs are ignored because they are usually no-op or erroneous executions and make a poor validation baseline. Load dates come from that run's `conf` when present, otherwise from `data_interval_start` and `data_interval_end` (end date uses the exclusive-interval rule: calendar day before `data_interval_end`). When the resolved window has `load_start_date >= load_end_date`, the script bumps `load_end_date` by one day (API-ingestion DAGs need `end > start`). Prefer explicit `--load-start-date` / `--load-end-date` for API DAGs instead of relying on `--from-prod-run` alone. DAGs whose prod DAG has not had a qualifying success in the last `--prod-run-recency-days` (default 7) are skipped unless `--no-prod-run-recency-filter` is set.

### Stale validation tables

If a validation run fails with a Delta **schema mismatch** or **location already exists** error, the leftover `cluster_validation` table from a prior run may block the next attempt. **`DROP TABLE` only removes the UC metastore entry** — delete the underlying S3 prefix as well, then re-trigger.

1. Drop the UC table (from the failing task log: `cluster_validation.datalake_<schema>___<table>`):

```sql
DROP TABLE IF EXISTS cluster_validation.datalake_amplitude_page_viewed_events___schedule_search_listing_events;
DROP TABLE IF EXISTS cluster_validation.datalake_hub_services___business_unit;
```

2. Remove the table data prefix on S3. Validation writes under:

`s3://{datalake_bucket}/validation/cluster_validation/{prod_database}/{validation_table_name}/`

where `{prod_database}` is the prod UC database (segment before `___` in the validation table name) and `{validation_table_name}` is the full validation table name.

For prod (`datalake_bucket` = `5a-datalake-prod`):

```bash
aws s3 rm s3://5a-datalake-prod/validation/cluster_validation/datalake_amplitude_page_viewed_events/datalake_amplitude_page_viewed_events___schedule_search_listing_events/ --recursive
aws s3 rm s3://5a-datalake-prod/validation/cluster_validation/datalake_hub_services/datalake_hub_services___business_unit/ --recursive
```

For forno, use bucket `5a-datalake-forno` and the same path suffixes. Confirm the location in Databricks with `DESCRIBE TABLE EXTENDED cluster_validation.<table>` if unsure.

**Re-run / resume:** Before each validation DAG, the script queries recent Airflow runs (`--dag-runs-lookback`, default 25): it **resumes** monitoring any active run (`queued` / `running` / `deferred`), **skips** when the most recent terminal run finished within `--validation-cooldown-hours` (default 2h, success or failure), **skips** when the most recent terminal run is `success` (cluster validation is a smoke test; one success is enough signal), and **triggers** when the last run failed or there is no prior success. Use `--force-retrigger` to run again after an older success; cooldown still applies. `--from-prod-run` only chooses the load window sent on **trigger**; it does not affect skip. Dry-run `SKIP` lines include the last successful run id (e.g. `already validated (last run success: manual__...)`). Transient API errors during polling are retried with backoff until the run finishes or `--timeout` is reached.

**Live progress:** status lines append `(successful/failed/skipped/total, N active)`. `skipped` counts DAGs that exited without monitoring (cooldown, too-long `dag_id`, prod-window skip, etc.). `RESUME` / `TRIGGERED` DAGs stay in `active` until monitoring finishes, then move to `successful` or `failed`. Invariant: `successful + failed + skipped + active + queued ≤ total`.

**Databricks cluster name length:** Databricks limits cluster / job-cluster keys to 100 characters. Bietlejuice sets `cluster_name` to `{{ dag.dag_id }}_{{ run_id }}` in `prod_conf.yml`, so validation DAG ids longer than **56 characters** are skipped automatically (reserving 43 characters for `_` plus a worst-case Airflow `run_id` such as `scheduled__2026-06-11T15:48:16.516894+00:00`). Examples skipped by the batch script: `bietlejuice.arquivo_confidencial_integration_report__validation` (63 chars), `bietlejuice.enrich_braze_events_user_centric_periodicity__validation` (68 chars).

## Eligibility

```bash
python scripts/list_cluster_validation_eligible_dags.py
```

Phase 1: `query_delta`, `query`, `dw_query`, `metric_query` without unsupported `load_spark_job` (unless opted in).

Phase 2 (implemented, PR2–PR5): `cdc`, `dms_cdc`, `gsheets`, `database_pull`, `api_ingestion`, `reverse`, `core_model`, `qube_dimension`, `qube_measure`, `qube_metric`.

Phase 2 (pilot): `wonka` — shadow `__validation` DAGs with write redirect to `cluster_validation.wonka___*` (see [Wonka pilot](#wonka-pilot) below).

Phase 2 (excluded / future work): `query_view` — see [Exclusions](#exclusions) below.

## Wonka pilot

Wonka feature sets (QuintoML `jobs/wonka/*/configs/prod.yml`) can opt in to cluster validation by adding a top-level `validation.cluster` block. The validation DAG:

- Uses a `consolidation_*` cluster preset (Graviton) while `WonkaWorkflow` still merges the `wonka_cluster` runtime overlay (PEX init, Vault, env vars).
- Skips `optimize_delta_tables` and `load_cdf_to_datazord` (no prod Kafka CDF traffic).
- Redirects pipeline output via `load_wonka.py` env injection and `WonkaRunner` writer remapping to `cluster_validation.wonka___<feature_set>` (and `__latest` tables).

Pilot DAGs: `quintoml.wonka.user_visits__validation`, `quintoml.wonka.house_main__validation`.

Fleet auto-generation for Wonka DAGs remains deferred (see Phase 6 in the wiring plan).

## Exclusions

### query_view

`query_view` creates Trino/Spark views only; it does not materialise any table. There are no write-target rows to redirect, and no `cluster_validation` tables are emitted. View creation on a validation cluster is harmless but does not test compute behaviour, so `query_view` is **excluded** from Phase 2 write-target wiring (future work if view DDL compatibility testing is needed).

### access / reverse export DAGs

Custom Spark jobs that **export** data to external systems (SQS, SNS, S3, Birdie API, etc.) must **not** redirect reads to `cluster_validation` shadow tables. Validation runs inject `--target-database-name` / `--target-table-name` for consistency with other custom jobs, but the job should:

1. Call `is_validation_run(target_database_name, target_table_name)` and **return early** (skip the export).
2. Keep reading from **prod** sources (`reverse_birdie.{table}`, etc.) when not in validation mode.

See `load_into_sqs.py` and `load_into_birdie_api.py` for the pattern. Misusing `resolve_datalake_write_target` on the read path causes `TABLE_OR_VIEW_NOT_FOUND` on non-existent shadow tables.

### Validation conf exceptions

Some prod DAGs do not use the generic `load_start_date` / `load_end_date` window that `trigger_cluster_validation_dags.py --from-prod-run` derives from `data_interval_end - 1 day`. Register them in [`scripts/cluster_validation_conf_exceptions.py`](../../scripts/cluster_validation_conf_exceptions.py):

| Prod DAG | Resolver | Why |
| -------- | -------- | --- |
| `bietlejuice.text2filter_evals` | `exception:text2filter_single_day` | Single S3 partition per run (`data_interval_start`), not a multi-day window |
| `bietlejuice.cyber_legal` | `exception:cyber_legal_3day_window` | Declaration uses `load_end = load_start + 2 days`, not `interval_end - 1` |
| `bietlejuice.greenhouse_v3` | `exception:greenhouse_v3_single_day` | Single-day `updated_at` API window; pairs with validation-mode date scoping in `load_greenhouse_v3_raw.py` |

Dry-run output shows the resolver in the **SRC** column (`conf`, `data_interval`, or `exception:*`). DAGs that consume non-standard conf keys may also need declaration `get_date_param` wiring (see `text2filter_evals` `load_start_date`).

To add a new exception: implement a resolver, register it in `VALIDATION_CONF_EXCEPTIONS`, extend `LoadWindowSource` in `cluster_validation_reference.py`, and add unit tests in `tests/unit/scripts/test_cluster_validation_conf_exceptions.py`.

## UC grants

Job clusters need write access to schema `cluster_validation` in `quintoandar_prod` (one-time platform grant).
