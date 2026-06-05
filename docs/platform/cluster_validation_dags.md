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
7. **Photon alignment:** prod Photon clusters keep `runtime_engine: PHOTON`; worker and driver topology are mapped to the Graviton `*gd` families so local SSD expectations remain explicit.
8. Emit `validation.cluster.custom_configurations` only when effective prod differs from the validation preset defaults. Dictionary fields are diffed recursively (`spark_conf`, `spark_env_vars`, `aws_attributes`, etc.); list/scalar fields are emitted as full replacement values (`init_scripts`, `custom_tags` when list-shaped, `runtime_engine`, etc.).
9. **Preset-only fields:** if the prod preset has fields the consolidation preset does not have, emit them explicitly in `validation.cluster.custom_configurations`. Example: `custom_cluster_with_sedona` defines an extra Sedona `init_scripts` entry in `prod_conf.yml`; validation must carry that list explicitly because the consolidation preset only has the default `bi-etl-ejuice/init_script.sh`.
10. **Top-level cluster args:** declaration-level `custom_libraries`, `access_control_list`, and `databricks_conn_id` stay top-level under `validation.cluster`; they are not written into `custom_configurations`.

**Skip validation** when prod is already the sole consolidation preset that matches the topology (e.g. prod `consolidation_m_memory_cluster` with `r6g.2xlarge` worker and driver). The generator omits the `validation:` block entirely.

When validation is emitted, `validation.cluster.type` must still differ from prod `cluster.type` (enforced by `DAGDeclarationValidator`).

Existing validation blocks are also checked against generator output. `validate-cluster-validation-files` fails when a validation-stage `*_cluster.yml` is missing generated effective-prod overrides, so stale blocks should be regenerated instead of relying on runtime fallback behavior.

### Prod topology normalization (Graviton 6g)

When `extract-cluster-validation-files` writes or regenerates `*_cluster.yml`, it **normalizes Databricks prod** `custom_configurations` topology (`node_type_id`, `driver_node_type_id`, nested `core_nodes` / `task_nodes`) using the same `map_instance_type_to_graviton` rules as validation preset selection (`m5a` → `m6g`, `r5d` → `r6g`, photon presets → `*gd` where applicable). EMR clusters are left unchanged.

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
- Must differ from prod `cluster.type`
- DAGs with `load_spark_job` need `validation.allow_custom_spark_job: true`

## Generated Airflow DAG

The compiler emits a second DAG: `bietlejuice.{dag_name}__validation`

- `schedule`: manual only (`null`)
- No `dependencies.yaml` dataset wiring
- Load tasks do not publish datasets (`produce_datasets=false`)
- Cluster preset from `validation.cluster`
- Airflow tag: `cluster_validation`

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
| `--force-retrigger` | Always trigger; ignore existing Airflow runs |
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

**`--from-prod-run` load window:** For each validation DAG, the script reads the matching prod DAG (`bietlejuice.{name}`, without `__validation`). Among successful prod runs in the last `--prod-run-lookback-days` (default 14), it picks the run with the shortest duration (ties: most recent `start_date`). Load dates come from that run's `conf` when present, otherwise from `data_interval_start` and `data_interval_end` (end date uses the exclusive-interval rule: calendar day before `data_interval_end`). DAGs whose prod DAG has not succeeded in the last `--prod-run-recency-days` (default 7) are skipped unless `--no-prod-run-recency-filter` is set.

**Re-run / resume:** Before each validation DAG, the script queries recent Airflow runs (`--dag-runs-lookback`, default 25): it **resumes** monitoring any active run (`queued` / `running` / `deferred`), **skips** when the most recent terminal run is `success` (cluster validation is a smoke test; one success is enough signal), and **triggers** when the last run failed or there is no prior success. Use `--force-retrigger` to run again after a success. `--from-prod-run` only chooses the load window sent on **trigger**; it does not affect skip. Dry-run `SKIP` lines include the last successful run id (e.g. `already validated (last run success: manual__...)`). Transient API errors during polling are retried with backoff until the run finishes or `--timeout` is reached.

**Databricks cluster name length:** Databricks limits cluster names to 100 characters. Bietlejuice sets `cluster_name` to `{{ dag.dag_id }}_{{ run_id }}` in `prod_conf.yml`, so validation DAG ids longer than **64 characters** are skipped automatically (reserving 35 characters for `_` plus a typical Airflow `run_id`). Example: `bietlejuice.enrich_braze_events_user_centric_periodicity__validation` (68 chars) is not triggered by the batch script.

## Eligibility

```bash
python scripts/list_cluster_validation_eligible_dags.py
```

Phase 1: `query_delta`, `query`, `dw_query`, `metric_query` without unsupported `load_spark_job` (unless opted in).

Phase 2 (implemented, PR2–PR5): `cdc`, `dms_cdc`, `gsheets`, `database_pull`, `api_ingestion`, `reverse`, `core_model`, `qube_dimension`, `qube_measure`, `qube_metric`.

Phase 2 (excluded / future work): `wonka`, `query_view` — see [Exclusions](#exclusions) below.

## Exclusions

### wonka

`load_wonka` is a pipeline runner that dispatches to other jobs at runtime. It cannot redirect table output without changes to the Wonka runner itself. `cluster_validation` DAGs for `wonka` workflow types are currently **not supported** — the validator will raise if `validation:` is set on a wonka DAG.

### query_view

`query_view` creates Trino/Spark views only; it does not materialise any table. There are no write-target rows to redirect, and no `cluster_validation` tables are emitted. View creation on a validation cluster is harmless but does not test compute behaviour, so `query_view` is **excluded** from Phase 2 write-target wiring (future work if view DDL compatibility testing is needed).

## UC grants

Job clusters need write access to schema `cluster_validation` in `quintoandar_prod` (one-time platform grant).
