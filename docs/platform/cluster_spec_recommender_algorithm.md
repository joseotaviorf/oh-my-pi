# Cluster Spec Recommender - Algorithm

Reference for [`scripts/recommend_cluster_specs.py`](../../scripts/recommend_cluster_specs.py).

Operational steps live in [`cluster_spec_recommender_runbook.md`](cluster_spec_recommender_runbook.md).

---

## Philosophy

The recommender is now **single-node-first**. A multi-node cluster is treated as a cost smell unless measured demand proves it needs multiple machines.

The reason is empirical:

- `core` and `fast_lane` have run predominantly single-node since April/May and stayed stable while running hot: p95 CPU/memory often lands around 80-97%.
- `opa` and `istio` tried single-node and reverted. Their blocker is not I/O wait; it is wall-clock versus hourly cadence. Their p95 wall time is already around 34-44 minutes of a 60 minute interval.
- Fleet data showed most spend has low worker CPU, and driver-bound plus idle-worker clusters are prime collapse candidates rather than keep-multi candidates.

Multi-node is kept only for narrow evidence exits: capacity over the largest single node, projected SLA breach, balanced hot driver and workers, or a spot/on-demand cost increase.

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
| `drv_cpu_p95 < 20%` and `drv_mem_p95 < 35%` | `driver_downsize` | Downsize single-node one tier |
| Otherwise | `healthy_single` | No validation config |

Multi-node branch:

1. Compute additive memory and core demand.
2. Pick the cheapest single node that holds demand at about 82% memory and 85% CPU.
3. If no single node fits, return `keep_multi_memory`, `keep_multi_compute`, or `keep_multi_balanced`.
4. Project post-collapse wall p95 and require it to be <= 80% of `schedule_interval_minutes`; otherwise `keep_multi_sla`.
5. If driver and workers are both hot, return `keep_multi_balanced`.
6. Compare projected single-node on-demand EC2 + DBU against actual blended cost. If collapse costs more, return `keep_multi_cost`.
7. Otherwise return `collapse_to_single`.
8. For every `keep_multi_*` exit, independently right-size the driver and workers, then keep only changes that reduce projected blended cost.

I/O wait is no longer an automatic keep gate. `opa`/`istio` showed that the real production blocker for small-file CDC jobs is cadence and wall-clock, not high CPU wait.

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

The recommender estimates wall-clock inflation after removing workers:

```text
projected_wall_p95 =
  wall_p95_min * (1 + (0.67 * worker_activity + 0.15 * worker_burst) * worker_multiplier)
```

Where:

- `0.67` is calibrated from the fast_lane full worker-removal experience.
- `worker_activity` uses worker p50/p95 CPU and p95 memory pressure.
- `worker_burst` adds a small penalty for spiky p95 worker CPU, which protects OPA-like small-file CDC jobs.
- `worker_multiplier` scales with worker count and caps at 1.
- Near-hourly observed cadence is capped at 60 minutes when missed runs make `1440 / runs_per_day` look longer than the actual schedule.

Collapse is allowed only when:

```text
projected_wall_p95 <= 0.80 * schedule_interval_minutes
```

This keeps hourly CDC shapes like `opa` and `istio` multi-node when they are already using most of the interval.

---

## Multi-Node Right-Sizing

When the single-node path is rejected, the recommender keeps the DAG multi-node but still looks for independent savings on the driver and workers.

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

## Cost Guard

Single-node clusters are on-demand. Multi-node workers are often spot. The cost guard compares the rejected single-node candidate against `arm_avg_cost_per_run_usd` (negotiated total USD per run from telemetry):

```text
single_node_projected_cost =
  single_node_on_demand_ec2_per_run
  + projected_dbu_cost

single_node_on_demand_ec2_per_run =
  single_node_on_demand_ec2_per_hour * projected_runtime_hours

projected_runtime_hours =
  current_wall_p50_hours * collapse_wall_inflation

projected_dbu_cost =
  current_dbu_cost
  * recommended_vcpus / current_vcpus
  * projected_runtime_hours / current_wall_p50_hours
```

The break-even intuition is:

```text
single_OD < driver_OD + worker_count * worker_OD * 0.37
```

Because spot is only 37% of on-demand, busy spot-heavy clusters can be cheaper as multi-node. Those land in `keep_multi_cost`.

Example:

```text
Current: m6g.large OD driver + 2 x m6g.2xlarge spot workers
EC2/hr: 0.077 + 2 * 0.308 * 0.37 = 0.305

Collapse candidate: m6g.4xlarge OD
EC2/hr: 0.616
```

That collapse more than doubles EC2 before DBU effects, so it is blocked.

For kept multi-node recommendations, the cost guard evaluates the actual driver/worker resize:

```text
multi_node_projected_cost =
  projected_dbu_cost
  + projected_driver_ec2_per_run
  + projected_worker_ec2_per_run

projected_worker_ec2_per_run =
  measured_worker_ec2_per_run
  * (new_worker_count * new_worker_on_demand_price)
    / (old_worker_count * old_worker_on_demand_price)
  * worker_reduction_wall_inflation
```

This preserves the observed spot/on-demand blend from telemetry while scaling it by the recommended worker type, worker count, and projected runtime. If the combined driver/worker proposal is not cheaper, the recommender falls back to the current multi-node shape plus any driver-only minimization and records `resize_blocked_cost` in `actions`.

The report keeps accepted and blocked cost estimates separate:

- `est_cost_delta_pct` is the accepted recommendation's estimated per-run delta.
- `blocked_cost_delta_pct` is the rejected cost-guard candidate's estimated per-run delta.
- `--list` renders both as `est -12% (+35%)`: accepted savings first, blocked increase in parentheses.
- If no resize is accepted, the accepted delta is `0%`, for example `est 0% (+35%)`.

---

## Actions Column

The existing `cohort` remains the classification: why the recommendation took a path. The `actions` column is the decision trace: what was attempted, accepted, or blocked.

Vocabulary:

- Topology: `collapse_to_single`, `keep_multi_node`
- Driver: `reduce_driver`, `keep_driver`
- Worker type: `reduce_worker_type`, `keep_worker_type`
- Worker count: `reduce_worker_count`, `keep_worker_count`
- Blocked levers: `worker_count_blocked_sla`, `resize_blocked_cost`
- No-op fallthrough: `no_change`

Examples:

```text
collapse_to_single
keep_multi_node|reduce_driver|reduce_worker_type|reduce_worker_count
keep_multi_node|reduce_driver|reduce_worker_type|worker_count_blocked_sla
keep_multi_node|resize_blocked_cost
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
| `collapse_to_single` | Yes | Multi-node demand fits single-node, SLA, and cost |
| `keep_multi_sla` | Yes | Collapse would violate cadence guard; keep multi-node and right-size driver/workers |
| `keep_multi_memory` | Yes | Additive memory exceeds largest single node; keep multi-node and right-size driver/workers |
| `keep_multi_compute` | Yes | Additive cores exceed largest single node; keep multi-node and right-size driver/workers |
| `keep_multi_balanced` | Yes | Driver and workers are both hot; keep multi-node and right-size driver/workers when headroom exists |
| `keep_multi_cost` | Yes | Single-node on-demand would cost more; keep multi-node and right-size driver/workers when cheaper |
| `protect_oom_risk` | Yes | Single-node near OOM; promote to a higher-memory family (size up only when already on `r6g`) |
| `driver_downsize` | Yes | Single-node driver has excess headroom; downsize |
| `healthy_single` | No | Single-node is acceptable |
| quality review cohorts | No | Need data, stable config, or price confidence first |
| `autoscale_review` | No | Fixed-size recommender does not alter autoscale clusters |

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
