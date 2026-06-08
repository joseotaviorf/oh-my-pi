# Cluster Spec Recommender - Runbook

Step-by-step guide for generating single-node-first cluster recommendations and shadow validation configs.

**Script:** [`scripts/recommend_cluster_specs.py`](../../scripts/recommend_cluster_specs.py)  
**Algorithm:** [`cluster_spec_recommender_algorithm.md`](cluster_spec_recommender_algorithm.md)  
**Validation DAG reference:** [`cluster_validation_dags.md`](cluster_validation_dags.md)

The recommender is report-only. It writes validation configs only; it does not mutate production `cluster:`.

---

## Prerequisites

1. Work from a branch containing `scripts/recommend_cluster_specs.py`.
2. VPN connected for live Trino.
3. Repo root is `bi-etl-ejuice`.
4. Use `uv run`; do not use bare `python3` or `pip`.

---

## 1. Preview Cohorts

```bash
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino --list
```

Useful flags:

| Flag | Default | Purpose |
| --- | ---: | --- |
| `--days` | `90` | Lookback window |
| `--min-days` | `3` | Minimum ARM calendar days |
| `--min-runs` | `3` | Minimum ARM runs |
| `--trino-host` | prod Trino hostname | Trino endpoint; overridden by `TRINO_HOST` env var when set |
| `--use-amd-history` | off | Optional AMD fallback for collapse-only candidates |

Set `TRINO_HOST` to point at a non-prod Trino endpoint without changing the command line:

```bash
export TRINO_HOST=trino.apps.data-stg.example.zone
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py --trino --list
```

Example output:

```text
[collapse_to_single] bietlejuice.some_dag  -> consolidation_m_general_single_node_cluster  est -38%
[keep_multi_sla] bietlejuice.hourly_cdc  -> consolidation_s_general_cluster  est -9%
[keep_multi_cost] bietlejuice.blocked_dag  -> consolidation_m_general_cluster  est 0% (+35%)
```

Use the `actions` column in `recommendations.csv` / JSON to understand the decision trace. `cohort` explains why the DAG landed on a path; `actions` explains what changed or was blocked.

Examples:

- `collapse_to_single`
- `keep_multi_node|reduce_driver|reduce_worker_type|reduce_worker_count`
- `keep_multi_node|reduce_driver|reduce_worker_type|worker_count_blocked_sla`
- `keep_multi_node|resize_blocked_cost`

The first `est` percentage is the accepted recommendation's estimated per-run delta. A percentage in parentheses is the rejected cost-guard candidate. For example, `est 0% (+35%)` means no resize was accepted and the blocked candidate was estimated to increase cost by 35%.

---

## 2. Read Cohorts

Actionable cohorts:

| Cohort | What to do |
| --- | --- |
| `collapse_to_single` | Validate the recommended single-node cluster |
| `keep_multi_sla` | Keep multi-node; validate emitted driver, worker type, and worker count changes |
| `keep_multi_memory` | Keep multi-node; validate emitted driver, worker type, and worker count changes |
| `keep_multi_compute` | Keep multi-node; validate emitted driver, worker type, and worker count changes |
| `keep_multi_balanced` | Keep multi-node; validate emitted driver, worker type, and worker count changes |
| `keep_multi_cost` | Keep multi-node; validate cheaper emitted changes, or skip when `actions` shows `resize_blocked_cost` |
| `protect_oom_risk` | Promote single-node to a higher-memory family before any downsizing wave (size up only when already on `r6g`) |
| `driver_downsize` | Downsize single-node driver |

Non-actionable cohorts:

- `needs_more_arm_data`
- `needs_more_telemetry`
- `mixed_config_review`
- `spill_pressure_review`
- `cost_confidence_review`
- `healthy_single`
- `autoscale_review`

The older keep/downsize cohort names are not the target decision surface for the single-node-first model. A driver-bound or I/O-waiting multi-node cluster is now still evaluated through additive sizing, SLA, and cost.

---

## 3. Generate Reports and Validation Configs

```bash
mkdir -p /tmp/cluster-rightsizing

uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml
```

Outputs:

| File | Purpose |
| --- | --- |
| `recommendations.csv` | Main review report |
| `recommendations.json` | Same data in JSON |
| `validation_configs.yml` | Validation blocks for actionable DAGs |

For offline CSV input:

```bash
uv run --no-project --with pandas \
  python scripts/recommend_cluster_specs.py \
  --metrics-csv arm_metrics.csv \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml
```

The CSV must include the fields emitted by `build_sql()`, especially cadence and cost fields: `runs_per_day`, `schedule_interval_minutes`, `arm_avg_ec2_cost_usd`, `arm_avg_dbu_cost_usd`, `ec2_spot_hours`, and `ec2_on_demand_hours`.

---

## 4. Review Before Writing Files

Open `recommendations.csv`.

Start with:

- `collapse_to_single`
- `confidence = high`
- clear negative `est_cost_delta_pct`
- stable dominant config shares (`>= 0.80`)

Review carefully:

- `keep_multi_sla`: usually high-frequency DAGs. `opa`/`istio` are the reference shape.
- `keep_multi_cost`: collapse would move cheap spot worker capacity to an on-demand single node.
- `actions`: decision trace. Look for `reduce_driver`, `reduce_worker_type`, `reduce_worker_count`, `worker_count_blocked_sla`, and `resize_blocked_cost`.
- `protect_oom_risk`: handle before cost-saving waves; expect `m6g→r6g` at the same tier, not a same-family size-up.
- `medium-x86`: AMD fallback only.

Do not promote directly from the report. Every change needs a validation DAG run.

---

## 5. Write Validation Blocks

### Auto-write

```bash
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml \
  --write-cluster-files
```

This upserts `validation:` into each DAG's `*_cluster.yml` and preserves prod `cluster:`.

### Manual copy

Copy selected entries from `validation_configs.yml`.

Single-node exact preset:

```yaml
cluster:
  type: consolidation_m_general_cluster
  databricks_conn_id: databricks_new

validation:
  cluster:
    type: consolidation_m_general_single_node_cluster
    databricks_conn_id: databricks_new
```

Single-node with larger override:

```yaml
cluster:
  type: consolidation_xl_memory_cluster
  databricks_conn_id: databricks_new

validation:
  cluster:
    type: consolidation_xl_memory_single_node_cluster
    databricks_conn_id: databricks_new
    custom_configurations:
      driver_node_type_id: r6g.12xlarge
```

Keep multi-node but right-size driver and workers:

```yaml
cluster:
  type: consolidation_m_general_cluster
  databricks_conn_id: databricks_new

validation:
  cluster:
    type: consolidation_s_general_cluster
    databricks_conn_id: databricks_new
    custom_configurations:
      num_workers: 5
      driver_node_type_id: m6g.large
      node_type_id: m6g.xlarge
```

---

## 6. Validate and Compile

```bash
make validate-cluster-validation-files
make create-dag-files
```

Review the DAG diff:

```bash
git diff dags/ -- '*_cluster.yml' '*_dag.py'
```

The compiler creates shadow DAGs:

- `bietlejuice.<dag_name>__validation`
- tag `cluster_validation`
- output tables under `cluster_validation.*___*`

Production tables are not modified by validation runs.

---

## 7. Trigger Shadow Runs

Set Airflow credentials:

```bash
export AIRFLOW_API_URL="https://<your-airflow-host>/api/v1"
export AIRFLOW_AUTH_TOKEN="<token>"
```

Dry-run:

```bash
uv run --no-project python scripts/trigger_cluster_validation_dags.py \
  --dry-run \
  --lines growth \
  --from-prod-run
```

Trigger a pilot:

```bash
uv run --no-project python scripts/trigger_cluster_validation_dags.py \
  --lines growth \
  --dags enrich_lost_listings \
  --from-prod-run \
  --max-parallel 5
```

Useful flags:

| Flag | Purpose |
| --- | --- |
| `--lines platform,growth` | Scope by business line |
| `--dags dag1,dag2` | Short DAG folder names |
| `--dag-ids bietlejuice.foo__validation` | Full validation DAG ids |
| `--from-prod-run` | Reuse latest successful prod load window |
| `--force-retrigger` | Trigger again even if a validation run exists |

---

## 8. Decide Whether to Promote

Promote only after the validation DAG succeeds and runtime is acceptable.

Check:

- No task failures or retries beyond normal noise.
- No OOM or executor loss.
- Wall p95 still fits the schedule, especially for hourly jobs.
- Cost delta is negative for `collapse_to_single`.
- For `keep_multi_*`, the worker count is preserved and only driver capacity changed unless intentionally reviewed.

Promotion helper:

```bash
uv run python packages/bietlejuice-compiler/scripts/validation/promote_cluster_validation_to_prod.py \
  dags/growth/enrich_lost_listings/
```

Then:

```bash
make validate-cluster-validation-files
make create-dag-files
```

---

## Quick Workflow

```bash
# 1. Preview
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py --trino --list

# 2. Generate validation configs
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml

# 3. Optional: write validation blocks
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml \
  --write-cluster-files

# 4. Compile and validate generated DAG files
make validate-cluster-validation-files
make create-dag-files
```

---

## Guardrails

- Single-node is the default target, but **SLA and cost gates win**.
- Do not override the spot/on-demand cost model with external CSV prices; use `dim_ec2_price`.
- Do not reduce worker count for `keep_multi_*`; preserve current worker count and minimize driver only.
- Treat `core` and `fast_lane` as evidence that hot single-node can be acceptable.
- Treat `opa` and `istio` as evidence that hourly wall-clock pressure can require multi-node even for small data volumes.
- Never promote without a successful shadow validation run.
