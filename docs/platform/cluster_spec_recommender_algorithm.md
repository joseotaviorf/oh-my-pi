# Cluster Spec Recommender - Algorithm

Reference for [`scripts/recommend_cluster_specs.py`](../../scripts/recommend_cluster_specs.py).

Operational steps live in [`cluster_spec_recommender_runbook.md`](cluster_spec_recommender_runbook.md).

---

## Philosophy

The recommender is **bidirectional and cost-truthful**. It does not assume single-node is always better, nor multi-node. For every DAG it generates the feasible candidate shapes, prices each under one consistent model, and keeps the cheapest that does not regress the SLA. The cohort *is* the reason for the pick.

The reason is empirical:

- A multi-node cluster with a small **on-demand driver** plus a few **spot workers** can be cheaper than collapsing to a large on-demand single node, because spot is ~37% of on-demand. So collapse is not automatically a win.
- `core` and `fast_lane` run hot single-node (p95 CPU/memory ~80-97%) — genuinely good single nodes.
- `opa` and `istio` tried single-node and reverted. Their blocker is wall-clock versus hourly cadence, not I/O wait. Their p95 wall is already ~34-44 minutes of a 60 minute interval, so collapse breaks the SLA but a worker-type refinement does not.
- Photon (DBU ~3x) and local NVMe (EC2 ~+20%) are treated as cost-impacting and **normalized off** in every recommendation; the cost model prices the normalized shape.

Two independent levers drive the decision — one for the driver, one for the workers. If they converge on a single node, the pick is `collapse_to_single`; if they converge on a smaller multi-node shape, the pick is `right_size_multi`; if nothing beats the observed cost-or-SLA, the DAG is kept with a `keep_multi_*` reason.

---

## Data Source

The live query reads `dw_databricks_health.fact_databricks_dag_run` for successful orchestrated `bietlejuice.%` runs:

- `is_job_on_interactive = FALSE`
- `is_any_task_failed = FALSE`
- `is_any_databricks_run_failed = FALSE`
- `COALESCE(total_cost_usd, 0) > 0` (excludes zero-cost rows from a known ingestion bug on recent load dates)
- `NOT REGEXP_LIKE(airflow_dag_id, '__validation$')` (prod DAGs only in the main query)

ARM runs are identified with a case-insensitive Graviton regex:

```text
^([a-z][a-z0-9]*[0-9]g(d|n|b)?|a1)[.]
```

This covers `m6g`, `m6gd`, `m7g`, `c6g`, `r6gd`, `a1`, and mixed-case node types from Databricks.

The query selects the **total-cost-dominant** ARM cluster config per DAG (`SUM(total_cost_usd)`). If one config does not account for at least 80% of runs and cost share, the DAG goes to `mixed_config_review`.

### Cost Attribution

Costs follow the same chain as `fact_databricks_dag_run` attribution:

```text
dim_dbu_price (negotiated USD/DBU) ──┐
dim_ec2_price (on_demand USD/hr) ────┼──► fact_databricks_task_run ──► fact_databricks_dag_run ──► recommender
```

| Column | Unit | Aggregation | Use |
| --- | --- | --- | --- |
| `total_cost_usd` | USD | `SUM` (period), `AVG` (per run) | Cost basis, dominant-config ranking |
| `total_dbu_cost_usd` | USD | `SUM`, `AVG` | DBU component in cost projection |
| `total_ec2_cost_calculated_usd` | USD | `SUM`, `AVG` | EC2 component in cost projection |
| `total_dbu_consumed` | DBU (scalar) | `AVG` only | Sanity vs `dim_dbu_price`; never summed with USD |
| `total_dbu_list_cost_usd` | USD | — | **Not used** (audit-only list rate) |

`_current_cost_basis()` returns `arm_avg_cost_per_run_usd` (= `AVG(total_cost_usd)`). Implied $/DBU is a ratio: `AVG(total_dbu_cost_usd) / AVG(total_dbu_consumed)`.

### Key Inputs

| Field | Meaning |
| --- | --- |
| `arm_days`, `arm_runs` | Eligibility and confidence basis |
| `runs_per_day`, `schedule_interval_minutes` | Cadence proxy, currently `1440 / runs_per_day` |
| `wall_p50_min`, `wall_p95_min` | Runtime distribution |
| `drv_cpu_p50/p95`, `drv_mem_p50/p95` | Driver utilization |
| `wrk_cpu_p50/p95`, `wrk_mem_p50/p95` | Worker utilization |
| `worker_count`, `driver_node_type`, `worker_node_type` | Current topology and capacity |
| `arm_avg_cost_per_run_usd` | Per-run total USD (negotiated DBU + EC2) |
| `arm_avg_ec2_cost_usd`, `arm_avg_dbu_cost_usd` | Cost guard components |
| `arm_avg_dbu_consumed` | Per-run DBU intensity (sanity only) |
| `ec2_spot_hours`, `ec2_on_demand_hours` | Evidence of spot/on-demand blend |
| `is_any_photon` | Any run used Photon; recommendation normalizes it off (DBU ~3x) |
| `is_any_local_nvme` | Any run used a local-NVMe (`*gd`) node; recommendation normalizes it off (EC2 ~+20%) |
| spill and pricing flags | Quality gates |

### Instance Catalog

EC2 on-demand USD/hour is generated from [`dim_ec2_price.sql`](../../dags/platform/enrich_databricks_pricing/queries/enrich/dim_ec2_price.sql). Hardware specs (vCPU, RAM, family) live in [`scripts/instance_specs.yml`](../../scripts/instance_specs.yml). The generator [`scripts/generate_instance_catalog.py`](../../scripts/generate_instance_catalog.py) joins both into [`scripts/instance_catalog_data.py`](../../scripts/instance_catalog_data.py).

Spot is modeled as `0.37 × on_demand` (a 63% discount), matching `dim_ec2_price` seed derivation and `daily_cluster_health`.

---

## Guard Chain

Quality gates still run first:

| Guard | Cohort |
| --- | --- |
| Below `--min-days` or `--min-runs` | `needs_more_arm_data` |
| Autoscale topology | `autoscale_review` |
| Mixed dominant config | `mixed_config_review` |
| Missing required metrics | `needs_more_telemetry` |
| Any spill | `spill_pressure_review` |
| EC2 or DBU pricing confidence gap | `cost_confidence_review` |

Single-node branch:

| Guard | Cohort | Action |
| --- | --- | --- |
| `drv_mem_p95 >= 88%` | `protect_oom_risk` | Promote single-node to a higher-memory family at the same tier (`compute→general→memory`); if already on memory, step up one size tier |
| `drv_cpu_p95 <= 40%` and `drv_mem_p95 <= 70%` and a safe one-tier downsize exists | `driver_downsize` | Downsize single-node one tier (relaxed thresholds; projected mem/CPU must stay under the 82%/85% single-node targets) |
| Otherwise | `healthy_single` | No validation config |

Multi-node branch (bidirectional candidate selection, `_decide_multi`):

1. Build the **collapse** candidate: the cheapest single node holding additive demand at ~82% memory / ~85% CPU (`build_best_single_candidate`).
2. Build the **refined-multi** candidate: independently minimize the driver and resize the worker type/count, floored at two workers (`build_current_refined_candidate`). A 1-worker shape is strictly dominated by single-node, so it folds into the collapse comparison.
3. Filter each candidate:
   - **Core cap** — candidate total cores must not exceed observed total cores (never upsize).
   - **SLA** — projected p95 wall must be `<= max(0.80 * schedule_interval_minutes, observed wall_p95)` (never regress beyond the larger of the SLA target and what the DAG already runs at).
   - **Memory feasibility** for the collapse candidate.
   - The refined candidate must be a **genuine reduction** (driver, worker type, or count shrinks) — an unchanged shape is not a recommendation.
4. Price every surviving candidate (OD driver + spot workers + fleet DBU, Photon normalized off) and keep the **cheapest that beats the observed cost basis**. That candidate's label (`collapse_to_single` or `right_size_multi`) becomes the cohort.
5. If nothing beats cost-or-SLA, keep multi-node with the most informative reason: `keep_multi_memory` / `keep_multi_compute` / `keep_multi_balanced` (from the sizer), else `keep_multi_balanced` (hot driver + busy workers), else `keep_multi_sla` (collapse breaks cadence), else `keep_multi_cost`. The rejected candidate cost is surfaced as `blocked_cost`.

I/O wait is not an automatic keep gate. `opa`/`istio` showed the real production blocker for small-file CDC jobs is cadence and wall-clock, not high CPU wait.

---

## Additive Single-Node Sizer

Demand is computed from observed p95 utilization:

```text
required_mem_gb =
  driver_memory_gb * drv_mem_p95
  + worker_count * worker_memory_gb * wrk_mem_p95

required_cores =
  driver_vcpus * drv_cpu_p95
  + worker_count * worker_vcpus * wrk_cpu_p95
```

Percent values are divided by 100 in the implementation.

Candidate acceptance:

```text
required_mem_gb / candidate_memory_gb <= 0.82
required_cores / candidate_vcpus <= 0.85
```

Family is chosen from actual GiB-per-core demand, not the current instance family:

| Demand ratio | Preferred families |
| --- | --- |
| `<= 2 GiB/core` | compute, then general, then memory |
| `<= 4 GiB/core` | general, then memory |
| `> 4 GiB/core` | memory |

This intentionally demotes over-provisioned memory families. A cluster currently on `r6g.*` can land on `m6g.*` if the observed workload is not memory-heavy.

The sizer includes larger single-node candidates (`12xlarge`, `16xlarge`) even when no exact consolidation preset exists. In that case the validation config uses the nearest `xl` single-node preset plus `custom_configurations.driver_node_type_id`.

---

## SLA Guard

The SLA guard works on the **p95** wall (`_projected_wall_for_sla`), inflated for the shape change plus the Photon-off normalization the recommender always applies:

```text
projected_wall_p95 =
  wall_p95_min
  * shape_inflation        # 1.0 for a same-parallelism worker-type swap;
                           # collapse_wall_inflation for collapse;
                           # worker_reduction_wall_inflation for fewer workers
  * (2.0 if is_any_photon else 1.0)   # Photon normalized off doubles wall
```

A candidate passes when:

```text
projected_wall_p95 <= max(0.80 * schedule_interval_minutes, observed wall_p95)
```

The `max(..., observed)` ceiling is deliberate: a same-parallelism worker-type downsize keeps wall unchanged, so it must not be blocked just because the DAG already runs over its SLA target. Only candidates that **regress** wall (collapse, fewer workers, Photon-off) are held to the schedule target. This keeps hourly CDC shapes like `opa`/`istio` multi-node when collapsing, while still allowing a worker-type refinement.

`collapse_wall_inflation` keeps the calibrated `0.67` worker-activity term (from the fast_lane full worker-removal experience) plus a small `worker_burst` penalty for spiky p95 worker CPU. Near-hourly observed cadence is capped at 60 minutes when missed runs make `1440 / runs_per_day` look longer than the actual schedule.

---

## Multi-Node Right-Sizing (refined-multi candidate)

`build_current_refined_candidate` builds the smaller multi-node shape that competes against collapse. It uses two independent levers and floors workers at two (a 1-worker shape is dominated by single-node):

Driver:

- Compute observed driver memory/core demand from p95 utilization.
- Choose the cheapest ARM node that holds that demand at the 82% memory / 85% CPU targets.
- Use the same GiB-per-core family ordering as the single-node sizer, so a memory-family driver can move to general or compute when the observed demand allows it.

Workers:

- Compute per-node worker memory/core demand from p95 utilization.
- Pick the cheapest ARM worker type that holds the per-node demand at the same 82%/85% targets.
- Compute aggregate worker demand and conservatively reduce worker count by at most two nodes at a time, with a floor of two workers.
- Block the count reduction if the projected wall p95 exceeds 80% of schedule interval. Worker type changes may still proceed because they preserve parallelism.

Worker count wall inflation is intentionally simpler than full collapse:

```text
worker_reduction_wall_p95 =
  wall_p95_min * (1 + (old_worker_count / new_worker_count - 1) * worker_activity)
```

Where `worker_activity` is the max of worker p50/p95 CPU and p95 memory pressure normalized to the 85%/82% targets.

---

## Cost Engine

Every candidate is priced by `estimate_projected_total_cost` under one consistent model, so collapse and refined-multi are compared apples-to-apples:

```text
projected_cost =
    on_demand_driver_ec2_per_hour * wall_hours
  + spot_worker_ec2_per_hour * worker_count * wall_hours      # spot = 0.37 * on_demand
  + dbu_per_run * negotiated_usd_per_dbu                      # _USD_PER_DBU = 0.114
```

Key rules:

- **Driver is on-demand, workers are spot.** Recommendations never price (or emit) on-demand workers.
- **EC2 scales with runtime**, not a whole hour — a 5-minute run pays ~1/12 of the hourly price.
- **DBU per run** uses the fleet-derived non-Photon DBU/node-hour (`_FLEET_DBU_RATE`, loaded once at runtime from telemetry of non-Photon homogeneous clusters). When the fleet map cannot price a node it falls back to a vCPU-proportional estimate, and when the map is empty (offline/unit runs) it degrades to the legacy observed-DBU proxy so the tool still produces a cost.
- **Photon normalized off** multiplies the projected wall by `_PHOTON_OFF_WALL_INFLATION = 2.0` (the recommendation always assumes Photon is removed; DBU drops to the non-Photon fleet rate).
- **Photon demand adjustment** (`effective_demand()` when `is_any_photon`): sizing gates and additive-demand math use inflated CPU/memory telemetry — `_PHOTON_OFF_CPU_INFLATION = 1.20` on p50/p95 CPU, `_PHOTON_OFF_MEM_INFLATION = 1.30` on p50/p95 memory — so collapse, downsize, OOM, and multi levers assume STANDARD-runtime headroom. CSV observed columns stay raw; only decision logic uses effective demand.
- **NVMe normalized off** is implicit: recommended node types are the non-`gd` equivalents, so the ~20% NVMe EC2 premium is gone.

The break-even intuition is unchanged — because spot is only 37% of on-demand, a small OD driver plus spot workers can beat a large OD single node:

```text
single_OD  vs  driver_OD + worker_count * worker_OD * 0.37
```

Example:

```text
Current: m6g.large OD driver + 2 x m6g.2xlarge spot workers
EC2/hr: 0.077 + 2 * 0.308 * 0.37 = 0.305

Collapse candidate: m6g.4xlarge OD
EC2/hr: 0.616  → collapse more than doubles EC2; refined-multi wins.
```

## Candidate Selection and the Cost Basis

`_decide_multi` keeps the cheapest surviving candidate whose projected cost is **below the observed cost basis** (`arm_avg_cost_per_run_usd`, the true blended USD/run from telemetry). A candidate that does not beat the basis is rejected, and its cost is surfaced as the blocked alternative.

The report keeps accepted and blocked cost estimates separate:

- `est_cost_delta_pct` is the accepted recommendation's estimated per-run delta.
- `blocked_cost_delta_pct` is the cheapest rejected candidate's estimated per-run delta.
- `--list` renders both as `est -12% (+35%)`: accepted savings first, blocked increase in parentheses.
- When nothing is accepted (a `keep_multi_*` pick), the accepted delta is `0%`, for example `est 0% (+35%)`.

---

## Actions Column

The existing `cohort` remains the classification: why the recommendation took a path. The `actions` column is the decision trace: what was attempted, accepted, or blocked.

Vocabulary:

- Topology: `collapse_to_single`, `keep_multi_node`
- Driver: `reduce_driver`, `keep_driver`
- Worker type: `reduce_worker_type`, `keep_worker_type`
- Worker count: `reduce_worker_count`, `keep_worker_count`
- Blocked levers: `worker_count_blocked_sla`
- Normalizations: `disable_photon` (also sets `runtime_engine: STANDARD`), `drop_nvme` (recommended nodes use the non-`gd` family)
- No-op fallthrough: `no_change`

Normalizations are appended to whatever shape decision was made (including an otherwise-healthy DAG), because the cost model already assumes Photon and NVMe are removed. Recommended workers are always spot — the recommender never emits `ON_DEMAND` for workers.

Examples:

```text
collapse_to_single
keep_multi_node|reduce_driver|reduce_worker_type|reduce_worker_count
keep_multi_node|keep_driver|reduce_worker_type|worker_count_blocked_sla
collapse_to_single|disable_photon|drop_nvme
keep_multi_node
```

---

## Driver and Worker Overrides

For kept multi-node cohorts, the recommender may emit a smaller driver, a smaller worker type, a lower worker count, or any combination that passes the SLA and cost guards.

This reflects the production pattern used by `istio`: small on-demand driver, spot workers doing the parallel work, but now also considers whether those workers are oversized.

Validation config example:

```yaml
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

## Cohorts

| Cohort | Actionable | Meaning |
| --- | ---: | --- |
| `collapse_to_single` | Yes | The cheapest surviving candidate is a single node that beats observed cost within SLA |
| `right_size_multi` | Yes | The cheapest surviving candidate is a genuinely smaller multi-node shape (driver/worker type/count) that beats observed cost within SLA |
| `keep_multi_sla` | No change | Nothing beat cost-or-SLA; collapse would break cadence |
| `keep_multi_memory` | No change | Additive memory exceeds the largest single node and no refinement wins |
| `keep_multi_compute` | No change | Additive cores exceed the largest single node and no refinement wins |
| `keep_multi_balanced` | No change | Driver and workers are both hot; no candidate beats cost-or-SLA |
| `keep_multi_cost` | No change | A feasible candidate exists but does not beat the observed cost basis |
| `protect_oom_risk` | Yes | Single-node near OOM; promote to a higher-memory family (size up only when already on `r6g`) |
| `driver_downsize` | Yes | Single-node driver has excess headroom; downsize one tier |
| `healthy_single` | No | Single-node is acceptable |
| quality review cohorts | No | Need data, stable config, or price confidence first |
| `autoscale_review` | No | Fixed-size recommender does not alter autoscale clusters |

`keep_multi_*` cohorts still surface a `blocked_cost` (the cheapest rejected candidate) but emit no shape change — only `disable_photon`/`drop_nvme` may still apply. A standalone Photon/NVMe normalization can make an otherwise-healthy DAG actionable.

The old `driver_cpu_bound_keep`, `driver_memory_pressure`, `io_bound_keep`, `memory_bound_keep`, `downsize_workers`, and `healthy_multi` paths are no longer the normal multi-node decision surface. Their names may remain in historical output but are not the target flow for new ARM recommendations.

---

## Validation Config Emission

Actionable recommendations emit `validation.cluster`, never prod `cluster`.

For exact presets:

```yaml
validation:
  cluster:
    type: consolidation_m_general_single_node_cluster
    databricks_conn_id: databricks_new
```

For larger single-node targets without exact presets:

```yaml
validation:
  cluster:
    type: consolidation_xl_memory_single_node_cluster
    databricks_conn_id: databricks_new
    custom_configurations:
      driver_node_type_id: r6g.12xlarge
```

For kept multi-node driver/worker right-sizing:

```yaml
validation:
  cluster:
    type: consolidation_s_general_cluster
    databricks_conn_id: databricks_new
    custom_configurations:
      num_workers: 5
      driver_node_type_id: m6g.large
      node_type_id: m6g.xlarge
```

### Normalization in the validation block

When the observed runs used Photon, the validation config drops the prod `runtime_engine: PHOTON` so the validation cluster runs `STANDARD` (the recommended preset's default) — `compute_validation_overrides` is passed `recommended_runtime_engine="STANDARD"` and removes the engine from the diff. NVMe normalization is reflected directly in the recommended node types (`*gd` → `*g`). Worker availability is never pinned to `ON_DEMAND` in a generated validation block.

---

## Validation Outcome Comparison

After recommendations are built, optional `--validation-outcomes PATH` compares actionable cohorts against existing `bietlejuice.*__validation` runs (same lookback window, `validation_min_runs` default 1).

For each matched prod DAG:

| Compared | Projected source | Actual source |
| --- | --- | --- |
| Cost per run | `projected.est_cost_per_run_usd` | `AVG(total_cost_usd)` from validation runs |
| Driver CPU p50 | `projected.est_drv_cpu_p50` | validation `APPROX_PERCENTILE` |
| Driver mem p95 | parsed from `projected.est_drv_mem_p95` | validation aggregate |
| Wall p95 | prod `wall_p95_min` (baseline) | validation wall p95 |

Initial thresholds:

- Cost: `pass` if `|delta_cost_pct| ≤ 15%`; `warn` if `≤ 30%`; else `fail`
- Driver CPU p50: `warn` if `|delta| > 15` percentage points
- Collapse cohorts: `warn` if validation wall p95 exceeds `1.2 ×` prod wall p95

Rows without validation history are skipped. See the runbook for operational usage.

---

## Verification

The implementation is covered by `tests/unit/scripts/test_recommend_cluster_specs.py`.

Required checks before relying on a recommendation batch:

```bash
uv run pytest tests/unit/scripts/test_recommend_cluster_specs.py
make check-style
uv run python scripts/generate_instance_catalog.py   # after seed or instance_specs.yml changes
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python scripts/recommend_cluster_specs.py --trino --list
```
