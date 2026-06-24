# Cluster Spec Recommender - Runbook

Step-by-step guide for generating bidirectional (cost-truthful) cluster recommendations and shadow validation configs.

**Script:** [`scripts/recommend_cluster_specs.py`](../../scripts/recommend_cluster_specs.py)  
**Validation YAML builder:** [`rightsizing_validation_config.py`](../../packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/rightsizing_validation_config.py) (same preset-diff rules as [`extract_cluster_validation_files.py`](../../packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/extract_cluster_validation_files.py))  
**Algorithm:** [`cluster_spec_recommender_algorithm.md`](cluster_spec_recommender_algorithm.md)  
**Validation DAG reference:** [`cluster_validation_dags.md`](cluster_validation_dags.md)

The recommender is report-only. It writes validation configs only; it does not mutate production `cluster:`.

Validation blocks are minimal: only `custom_configurations` that differ from the recommended preset defaults. `databricks_conn_id` is copied from prod `*_cluster.yml`; `--databricks-conn-id` is a fallback when prod omits it.

Validations that resolve to prod's effective spec are not written, and `--write-cluster-files` strips any stale `validation:` block whose spec now matches prod (e.g. after a promotion).

DAGs whose prod `cluster.type` starts with `emr_` (or resolve to an EMR `spark_version`) are excluded: no `validation:` block is emitted, and `--write-cluster-files` removes any stale validation section.

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
| `--min-days` | `3` | Minimum ARM calendar days (window eligibility) |
| `--min-runs` | `3` | Minimum ARM runs (window eligibility) |
| `--recent-era-min-days` | `1` | Min days on latest config era before sizing after a switch |
| `--recent-era-min-runs` | `2` | Min runs on latest config era before sizing after a switch |
| `--dominant-config-share-min` | `0.50` | Min dominant-config run **and** cost share to pass `mixed_config_review` |
| `--trino-host` | prod Trino hostname | Trino endpoint; overridden by `TRINO_HOST` env var when set |
| `--use-amd-history` | off | Optional AMD (x86) fallback for DAGs below ARM eligibility; same cohort/preset logic as ARM |
| `--memory-history-csv` | off | 90d ARM+AMD per-config memory history (`build_memory_history_sql`); floors memory demand at the long-window absolute-GB max |
| `--task-metrics-csv` | off | Per-task health percentiles (`build_task_sql`, `fact_databricks_task_run`); enables critical-task sizing, task duty-cycle wall model, and task-named review flags |
| `--amd-min-runs` | `10` | Minimum total x86 run count for AMD history pool |
| `--validation-outcomes` | off | Write `validation_outcomes.csv` comparing recommendations vs existing `__validation` runs (requires `--trino`) |
| `--validation-min-runs` | `1` | Minimum validation runs per DAG for outcome comparison |
| `--target-generation` | off | Retarget emitted driver+worker node types to this ARM generation (6/7/8); opt-in |
| `--target-generation-compute` | off | Per-family override for compute nodes (defaults to `--target-generation`) |
| `--target-generation-general` | off | Per-family override for general nodes (defaults to `--target-generation`) |
| `--target-generation-memory` | off | Per-family override for memory nodes (defaults to `--target-generation`) |
| `--retarget-scope` | `bounded` | `bounded`: retarget only DAGs with an actionable change; `fleet`: retarget all Gen-6 DAGs |
| `--include-validation-runs` | off | Union `__validation` runs into ARM metrics using **latest-generation-era** selection (see below) |
| `--validation-config-filter` | `same-latest` | With `--include-validation-runs`: `same-latest` keeps validation rows matching the latest cluster shape (NVMe-normalized); `all` unions every validation run on the metrics generation |
| `--dag-id-prefix` | `bietlejuice.%` | SQL LIKE prefix for dag-id scope (repeatable). Add `quintoml.wonka.%` for Wonka feature sets |
| `--quintoml-root` | `~/Work/quintoml` | QuintoML repo root when writing Wonka `validation:` blocks with `--write-cluster-files` |

Set `TRINO_HOST` to point at a non-prod Trino endpoint without changing the command line:

```bash
export TRINO_HOST=trino.apps.data-stg.example.zone
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py --trino --list
```

Example output:

```text
[collapse_to_single] bietlejuice.some_dag  -> consolidation_m_general_single_node_cluster  est -38%
[right_size_multi] bietlejuice.busy_dag  -> consolidation_s_general_cluster  est -22%
[keep_multi_cost] bietlejuice.blocked_dag  -> consolidation_m_general_cluster  est 0% (+35%)
```

Use the `actions` column in `recommendations.csv` / JSON to understand the decision trace. `cohort` explains which candidate won (or why none did); `actions` explains what changed, was blocked, or was normalized.

Examples:

- `collapse_to_single`
- `keep_multi_node|reduce_driver|reduce_worker_type|reduce_worker_count`
- `keep_multi_node|keep_driver|reduce_worker_type|worker_count_blocked_sla`
- `collapse_to_single|disable_photon|drop_nvme`
- `keep_multi_node`

The first `est` percentage is the accepted recommendation's estimated per-run delta. A percentage in parentheses is the cheapest rejected candidate. For example, `est 0% (+35%)` means no candidate beat the observed cost basis and the cheapest rejected one was estimated to increase cost by 35%. `drop_nvme` is applied on every actionable recommendation that observed local NVMe. `disable_photon` is **cost-gated, with one hard exception** — Photon is force-dropped when the winning shape lands on compute-family (`c*`) nodes, which Databricks rejects for Photon. Otherwise it — it appears only when dropping Photon actually beats keeping it (the recommender prices both worlds; see the "Photon quadrant search" section of the algorithm doc). When a *drop-Photon* candidate is sized, sizing uses **effective demand** (CPU ×1.20, memory ×1.30 on p50/p95) so it assumes STANDARD-runtime headroom; a keep-Photon candidate sizes on raw demand. Observed `drv_*` / `wrk_*` columns in the CSV remain the raw telemetry.

---

## 2. Read Cohorts

Actionable cohorts:

| Cohort | What to do |
| --- | --- |
| `collapse_to_single` | Validate the recommended single-node cluster |
| `right_size_multi` | Validate the smaller multi-node shape (emitted driver, worker type, and/or worker count) |
| `protect_oom_risk` | Promote single-node to a higher-memory family before any downsizing wave (size up only when already on `r6g`) |
| `driver_downsize` | Downsize single-node driver |

A `drop_nvme` action can appear on any actionable cohort above. `disable_photon` appears only when dropping Photon beats keeping it. When dropping the accelerators is what makes an otherwise-healthy DAG worth changing, it surfaces as an actionable `right_size_multi` (multi) or `healthy_single` (single) with a real, negative delta and a validation config — not a 0%-delta `keep_multi`. A `keep_multi_*` pick is now a true no-change (Photon and NVMe kept, because dropping Photon competed and lost).

Non-actionable cohorts (no shape change — kept as observed):

- `keep_multi_sla`, `keep_multi_memory`, `keep_multi_compute`, `keep_multi_balanced`, `keep_multi_cost` (no candidate beat cost-or-SLA; `blocked_cost` shows the cheapest rejected alternative)
- `needs_more_arm_data`
- `needs_more_telemetry`
- `recent_config_change` (team switched config recently; wait for new-era telemetry)
- `mixed_config_review`
- `spill_pressure_review`
- `cost_confidence_review`
- `healthy_single`
- `autoscale_review`

Orthogonal to cohorts, `review_flags` (`io_scan_review`, `driver_bound_review`) marks DAGs needing Spark-job-level review — see `docs/platform/cluster_rightsizing_spark_review_backlog.md` and `docs/platform/cluster_rightsizing_low_cpu_dag_analysis.md`. Flags never block a recommendation.

Under the bidirectional model the `keep_multi_*` cohorts no longer emit driver/worker resizes — a refinement that wins is reported as `right_size_multi` instead.

---

## 3. Generate Reports and Validation Configs

```bash
mkdir -p /tmp/cluster-rightsizing

ENVIRONMENT=prod uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
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
| `validation_outcomes.csv` | Optional; projected vs observed metrics for DAGs that already have `__validation` history (see §3b) |

For offline CSV input:

```bash
ENVIRONMENT=prod uv run --no-project --with pandas \
  python scripts/recommend_cluster_specs.py \
  --metrics-csv arm_metrics.csv \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml
```

The CSV must include the fields emitted by `build_sql()`, especially cadence and cost fields: `runs_per_day`, `schedule_interval_minutes`, `arm_avg_cost_per_run_usd`, `arm_avg_ec2_cost_usd`, `arm_avg_dbu_cost_usd`, `arm_avg_dbu_consumed`, `ec2_spot_hours`, and `ec2_on_demand_hours`.

Rows with `total_cost_usd = 0` are excluded at query time (known ingestion bug on recent load dates). Do not reintroduce `total_dbu_list_cost_usd` — cost authority is negotiated DBU + EC2 only.

### 3b. Compare Against Existing Validation Runs

When shadow validation DAGs already exist, compare projected recommendations against observed validation metrics:

```bash
ENVIRONMENT=prod uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml \
  --validation-outcomes /tmp/cluster-rightsizing/validation_outcomes.csv
```

`validation_outcomes.csv` joins actionable recommendations to `bietlejuice.*__validation` runs. Each row includes projected vs actual cost, driver CPU, memory, wall time, and an `outcome` label:

| `outcome` | Meaning |
| --- | --- |
| `pass` | Within thresholds (cost ±15%, CPU ±15 pp, wall inflation for collapse) |
| `warn` | Borderline drift (cost ±30%, memory, wall) |
| `fail` | Cost drift beyond warn threshold |
| `insufficient_validation_data` | No usable validation cost row |

Use this before promoting DAGs that already ran in shadow validation — it is a sanity check, not a substitute for a fresh validation run after changing the recommended spec.

### 3c. Post-migration / thin prod telemetry (`--include-validation-runs`)

After a fleet-wide generation bump (e.g. Gen6 → Gen7), prod rows in `fact_databricks_dag_run` may lag Airflow. Shadow `__validation` twins often already ran on the promoted shape. Use **latest-generation-era** metrics mode to size on Gen7 telemetry without waiting for DW sync.

**Default (flag off):** prod-only input, **dominant-config** selection (`rn_recent` + cost-dominant `config_changed_in_window`). Gen6 history in the lookback window can gate sizing via `recent_config_change` / `mixed_config_review`.

**With `--include-validation-runs`:** unions prod + `__validation` runs mapped to prod DAG ids. Per DAG:

1. Keep only the **highest ARM generation** in the window (e.g. Gen7; Gen6 dropped).
2. Pick the **latest cluster shape by time** within that generation (not cost-dominant).
3. Pool prod + validation runs on that shape (`--validation-config-filter same-latest`, NVMe-normalized; or `all` for every validation run on that generation).

Classifier migration noise is neutralized in SQL (`config_changed_in_window = false`, dominant shares = 1.0). SQL eligibility and the classifier use **`--recent-era-min-days` / `--recent-era-min-runs`** (defaults 1 / 2), not the stricter window `--min-days` / `--min-runs` (defaults 3 / 3), so thin Gen7 validation signal is not dropped when prod DW rows lag. `recommendations.csv` adds `arm_runs_prod`, `arm_runs_validation`, `metrics_era_generation`, and `metrics_include_validation`.

```bash
ENVIRONMENT=prod uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino --list \
  --include-validation-runs \
  --days 14
```

Optional: pin generation with `--target-generation 7` (metrics use Gen7 even when auto-max would differ). This is separate from `--target-generation` retargeting of **recommended** node types.

`--validation-outcomes` is unchanged — post-hoc projected-vs-observed check only; it does not feed the metrics pool.

---

## 4. Review Before Writing Files

Open `recommendations.csv`.

Start with:

- `collapse_to_single` and `right_size_multi`
- `confidence = high`
- clear negative `est_cost_delta_pct`
- stable dominant config shares (`>=` `--dominant-config-share-min`, default `0.50`)

Review carefully:

- `right_size_multi`: a smaller multi-node shape (small OD driver + spot workers) beat both collapse and the observed cost.
- `keep_multi_sla`: usually high-frequency DAGs. `opa`/`istio` are the reference shape.
- `keep_multi_cost`: a feasible candidate exists but does not beat the observed cost basis (`blocked_cost`).
- `actions`: decision trace. Look for `reduce_driver`, `reduce_worker_type`, `reduce_worker_count`, `worker_count_blocked_sla`, `disable_photon`, and `drop_nvme`.
- `protect_oom_risk`: handle before cost-saving waves; expect `m6g→r6g` at the same tier, not a same-family size-up.
- `medium-x86`: recommendation derived from AMD (x86) history via `--use-amd-history`. Same cohorts as ARM (`collapse_to_single`, `right_size_multi`, `keep_multi_*`, etc.); lower confidence because telemetry is pre-Graviton. Wall times in the report are observed (uncorrected); SLA/collapse math applies a 26.5% ARM speedup factor (`AMD_WALL_CORRECTION = 0.735`) before sizing.

### Wonka (`quintoml.wonka.*`)

Most Wonka prod configs are still x86 (`r5a`/`c5a`). Until ARM prod telemetry exists, run with both prefixes and AMD history:

```bash
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino --list \
  --dag-id-prefix 'bietlejuice.%' \
  --dag-id-prefix 'quintoml.wonka.%' \
  --use-amd-history
```

Rightsizing `--write-cluster-files` upserts `validation:` into QuintoML `jobs/wonka/*/configs/prod.yml` when `--quintoml-root` is set. Autoscale-heavy Wonka DAGs may classify as `autoscale_review` until autoscale-aware sizing lands; Phase 1 arch-migration blocks preserve autoscale via `generate_wonka_validation_blocks.py`.

Do not promote directly from the report. Every change needs a validation DAG run.

## Feedback loop (outcomes → promotion → watch)

See `docs/platform/cluster_rightsizing_feedback_loop_plan.md` for the design.

- **Outcomes table**: the daily platform DAG `rightsizing_outcomes`
  (`dags/platform/rightsizing_outcomes/`) writes
  `enrich_rightsizing_outcomes` — one row per validation Airflow run, paired
  with the reference prod run selected by `trigger_cluster_validation_dags.py`
  (`--from-prod-run`). `scripts/promote_rightsizing_validations.py` picks the
  **newest decisive** validation run per DAG (`is_decisive_validation_run` in
  the table): promote, reject, warn, or strong-positive extend — not blind
  latest timestamp. Filter BI aggregates with `is_decisive_validation_run = true`
  (one row per DAG). `reference_match_source` records pairing:
  `conf_run_id`, `conf_window`, or `heuristic`. Columns include
  `is_promote_eligible`, `outcome`, `promotion_action`, and attempt metadata.
  Promotion bar: ≥1 clean validation run, cost within +5% of prod, wall within
  +5% of prod reference (and cadence SLA for ≤2h schedules); `mem_p95 > 82`
  holds for one more run.
  Deploy note: table lives in `datalake_databricks_health.enrich_rightsizing_outcomes`
  (same UC schema as query_history / daily_cluster_health). The orphaned
  `datalake_rightsizing_outcomes.enrich_rightsizing_outcomes` entry from the v1
  schema can be dropped later; it does not block the new location.
- **Promotion gate**: export the outcomes table to CSV (Trino), then
  `uv run --python 3.12 python scripts/promote_rightsizing_validations.py
  --outcomes-csv <csv> --report-out <md>` — promotes eligible specs into the
  prod `cluster:` block, removes rejected validation sections, snapshots the
  pre-change baseline into `scripts/rightsizing_promotion_ledger.json`, and
  emits the promoted/rejected/extended report. Review the resulting diff as
  one PR.
- **Post-promotion watch**: `… --watch --outcomes-csv <fresh csv>` compares
  each promotion (<7 days old) against its ledger baseline and prints alert
  lines (cost > baseline +15%, failures, cadence-SLA breach) including the
  exact previous spec for revert.

---

## 5. Write Validation Blocks

### Auto-write

```bash
ENVIRONMENT=prod uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
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
- Wall p95 still fits the schedule for cadence-bound (≤2h interval) jobs; for everything else a wall increase is acceptable by policy as long as the cost delta is negative.
- Cost delta is negative for `collapse_to_single` and `right_size_multi`.
- For `right_size_multi`, confirm the emitted driver, worker type, and worker count match the intended shape and parallelism is preserved where wall matters.
- If `validation_outcomes.csv` was generated, review `outcome` and `delta_*` columns for DAGs with prior shadow runs.

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

# 2. Generate validation configs (ENVIRONMENT=prod resolves preset defaults)
ENVIRONMENT=prod uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml

# 3. Optional: compare vs existing __validation runs
ENVIRONMENT=prod uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino \
  --out-dir /tmp/cluster-rightsizing \
  --validation-outcomes /tmp/cluster-rightsizing/validation_outcomes.csv

# 4. Optional: write validation blocks
ENVIRONMENT=prod uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py \
  --trino \
  --out-dir /tmp/cluster-rightsizing \
  --validation-config /tmp/cluster-rightsizing/validation_configs.yml \
  --write-cluster-files

# 5. Compile and validate generated DAG files
make validate-cluster-validation-files
make create-dag-files
```

---

## Guardrails

- **Bidirectional, cost-truthful:** the cheapest candidate that beats the observed cost basis within SLA wins — neither single-node nor multi-node is privileged. **Memory, the core cap, and (for ≤2h schedules) the cadence SLA always win.** CPU is elastic: sizing uses `cpu_eff = p50 + 0.3·(p95−p50)` and the work-conserving wall model (`1 + f·(old/new cores − 1)`, f = p50-busy fraction) prices the stretch into projected cost. DAGs scheduled less often than every 2h have **no wall cap by policy** — the cost gate is the only brake.
- **Driver on-demand, workers spot:** recommendations never price or emit on-demand workers.
- **Photon quadrant + NVMe strip:** local NVMe (`drop_nvme`, `*gd`→`*g`) is removed on every actionable recommendation. Photon is a costed dimension — the recommender prices keep-Photon (raw demand, observed-anchored DBU, observed wall) and drop-Photon (`disable_photon`, `runtime_engine: STANDARD`, +100% wall, CPU ×1.20 / memory ×1.30 demand, non-Photon fleet DBU) across both the original and right-sized shapes (Q1-Q4) and keeps the globally cheapest that beats the observed cost. The offline DBU proxy divides observed DBU by `_PHOTON_DBU_PREMIUM = 3.0` when projecting Photon off.
- **Cost authority:** `arm_avg_cost_per_run_usd` = negotiated `total_cost_usd` per run (DBU USD + EC2 USD). `arm_avg_dbu_cost_usd` and `arm_avg_ec2_cost_usd` are components. `arm_avg_dbu_consumed` is a DBU scalar for sanity checks only — never sum USD and DBU columns. List DBU (`total_dbu_list_cost_usd`) is not used.
- **EC2 pricing:** on-demand USD/hour comes from [`dim_ec2_price.sql`](../../dags/platform/enrich_databricks_pricing/queries/enrich/dim_ec2_price.sql) via the generated catalog. Spot = `0.37 × on_demand`. Do not use external Amazon CSV prices in the pipeline.
- **ARM detection:** Graviton types match `^([a-z][a-z0-9]*[0-9]g(d|n|b)?|a1).` (case-insensitive), including `m6gd`, `m7g`, and `a1`.
- A `right_size_multi` recommendation floors workers at two; a 1-worker shape folds into single-node.
- Treat `core` and `fast_lane` as evidence that hot single-node can be acceptable.
- Treat `opa` and `istio` as evidence that hourly wall-clock pressure can require multi-node even for small data volumes.
- Never promote without a successful shadow validation run.

---

## Instance Catalog Maintenance

Hardware specs (vCPU, RAM, family) live in [`scripts/instance_specs.yml`](../../scripts/instance_specs.yml). On-demand prices are parsed from the `dim_ec2_price` seed. The recommender imports the generated [`scripts/instance_catalog_data.py`](../../scripts/instance_catalog_data.py).

When adding a new instance type to the fleet:

1. Add `on_demand_usd_hour` to [`dim_ec2_price.sql`](../../dags/platform/enrich_databricks_pricing/queries/enrich/dim_ec2_price.sql).
2. Add matching `vcpus` / `memory_gb` / `family` to `instance_specs.yml`.
3. Re-run `enrich_databricks_pricing` so the lake table updates.
4. Regenerate the recommender catalog:

```bash
uv run python scripts/generate_instance_catalog.py
```

The generator emits catalog entries only when both spec YAML and seed price exist; it warns on seed-only or spec-only mismatches.
