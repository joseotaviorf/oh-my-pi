# Recalibrating the cluster recommender's CPU/wall model

**Audience:** an agent (or engineer) picking this up a few days after a new
validation wave was staged, with no prior context.
**Goal:** re-fit the two calibrated constants in `scripts/recommend_cluster_specs.py`
against fresh prod↔validation telemetry, and decide whether they need to change.

## Background — what is calibrated and why

The recommender treats CPU as *elastic*: undersizing CPU stretches the wall
instead of failing the job (memory remains the only hard cap). Two constants
encode how much wall-stretch to expect:

| Constant | Current value | Meaning |
| --- | --- | --- |
| `_CPU_EFF_BURST_WEIGHT` | `0.3` | Sizing demand `cpu_eff = p50 + w·(p95 − p50)`. Lower = more aggressive shrink |
| `_WALL_CPU_BOUND_FRACTION_CAP` | `1.0` | Cap on `f` in the wall model `wall_ratio = 1 + f·(old_cores/new_cores − 1)`, `f` = aggregate p50-busy fraction of the observed cluster |

Both were fitted 2026-06-11 on 140 prod→validation shrunk pairs (median 1.6×
core cut). Findings then: implied CPU-bound wall fraction was 0 for 75% of
pairs; median observed wall ratio 0.87; `f = p50` was the best conservative fit
(83% coverage, median +0.24 wall-ratio overestimate).

**Why recalibrate:** that wave skewed toward DAGs the *old* (p95-capped)
algorithm already deemed safe. The post-2026-06 wave exercises much deeper cuts
(up to ~6× cores), where the work-conserving model is less proven. If the model
systematically *underestimates* wall stretch at deep cuts, projected costs are
too optimistic and some recommendations are wrong.

## Prerequisites

- Repo checkout, `make install` done (uv-managed; never bare `python3`).
- Trino access (the query helper opens browser-based external auth).
- At least ~3–5 days of validation runs since the wave was staged, so most
  validation DAGs have ≥3 successful runs.

## Step 1 — Pull prod↔validation pairs from Trino

Validation DAGs are named `<prod_dag_id>__validation` in
`dw_databricks_health.fact_databricks_dag_run`. Pull both sides over the same
window (14 days for prod gives stable percentiles; for validation use the days
since the wave started):

```bash
uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \
  python plugins/tars/skills/tars/scripts/execute_trino.py \
  --host trino.apps.data-prd.habitat.zone --catalog delta --external-auth \
  --query "$(cat /tmp/calibration.sql)" --csv-output /tmp/calibration.csv
```

`/tmp/calibration.sql` — one row per (dag, side):

```sql
WITH runs AS (
    SELECT
        REGEXP_REPLACE(airflow_dag_id, '__validation$', '') AS prod_dag_id,
        REGEXP_LIKE(airflow_dag_id, '__validation$')        AS is_validation,
        total_cost_usd,
        total_wall_clock_seconds / 60.0                     AS wall_min,
        weighted_avg_p50_worker_cpu_busy_percent            AS wrk_cpu_p50,
        weighted_avg_p95_worker_cpu_busy_percent            AS wrk_cpu_p95,
        weighted_avg_p50_driver_cpu_busy_percent            AS drv_cpu_p50,
        weighted_avg_p95_worker_mem_used_percent            AS wrk_mem_p95,
        driver_node_type, worker_node_type, worker_count
    FROM dw_databricks_health.fact_databricks_dag_run
    WHERE dt_dag_run_started >= CURRENT_DATE - INTERVAL '14' DAY
      AND airflow_dag_id LIKE 'bietlejuice.%'
      AND is_job_on_interactive = FALSE
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
      AND COALESCE(total_cost_usd, 0) > 0
)
SELECT
    prod_dag_id, is_validation, COUNT(*) AS n_runs,
    ROUND(AVG(total_cost_usd), 4)                    AS avg_cost,
    ROUND(APPROX_PERCENTILE(wall_min, 0.5), 1)       AS wall_p50,
    ROUND(APPROX_PERCENTILE(wrk_cpu_p50, 0.5), 1)    AS wrk_cpu_p50,
    ROUND(APPROX_PERCENTILE(wrk_cpu_p95, 0.95), 1)   AS wrk_cpu_p95,
    ROUND(APPROX_PERCENTILE(drv_cpu_p50, 0.5), 1)    AS drv_cpu_p50,
    ROUND(APPROX_PERCENTILE(wrk_mem_p95, 0.95), 1)   AS wrk_mem_p95,
    ARBITRARY(driver_node_type)  AS driver_node_type,
    ARBITRARY(worker_node_type)  AS worker_node_type,
    ARBITRARY(worker_count)      AS worker_count
FROM runs
GROUP BY 1, 2
HAVING COUNT(*) >= 3
```

Exclusions: drop any pair whose prod run was known-broken during the window
(check with the team; e.g. `facebook_insights_*` was excluded in 2026-06
because validation runs sat queued without starting — an infra issue, not a
model signal).

## Step 2 — Compute core ratios and implied CPU-bound fraction

For each DAG present on both sides, with vCPUs from
`scripts/instance_catalog_data.py` (`INSTANCE_SPECS_RAW[node]['vcpus']`):

```text
prod_cores  = drv_vcpus + wrk_vcpus * worker_count          (per side)
core_ratio  = prod_cores / val_cores                        (>1 = shrink)
wall_ratio  = val_wall_p50 / prod_wall_p50
f_implied   = (wall_ratio − 1) / (core_ratio − 1)           clip to [0, 1.5]
```

Keep only **shrunk** pairs (`core_ratio > 1.05`, `wall_ratio > 0`). Run with:

```bash
uv run --no-project --with pandas python <your analysis script>
```

(Use a PEP 723 script header if you want it reproducible; do not add workspace deps.)

## Step 3 — Evaluate the current model

For each candidate `f`-source, compute predicted wall ratio
`pred = (1 − f) + f·core_ratio` and compare:

| Candidate | f |
| --- | --- |
| current model | `wrk_cpu_p50/100` (prod side; fall back to `drv_cpu_p50`) |
| pessimistic | `wrk_cpu_p95/100` |
| blends | `p50 + α·(p95−p50)` for α ∈ {0.3, 0.5} |

Metrics that matter:

- **coverage** = share of pairs where `pred >= wall_ratio` (model is
  conservative). 2026-06 baseline: 83% for f=p50.
- **median error** = `median(wall_ratio − pred)`. Baseline: −0.24 (overestimate).
- Both **sliced by depth**: `core_ratio ≤ 2` vs `> 2`. The deep-cut slice is
  the one the 2026-06 fit could not see — weight it most.

## Step 4 — Decide

- **f=p50 coverage stays ≥ ~80% on the deep-cut slice** → no change. Record the
  numbers in the constants' comment block in `scripts/recommend_cluster_specs.py`
  (search `_WALL_CPU_BOUND_FRACTION_CAP`) with the new date.
- **Coverage degraded on deep cuts** → raise the burst weight first
  (`_CPU_EFF_BURST_WEIGHT` 0.3 → 0.4/0.5 makes *sizing* less aggressive, which
  indirectly shallows the cuts), and/or switch the wall model's `f` toward a
  blend by editing `_p50_busy_cores` (it currently uses pure p50). Prefer the
  smallest change that restores coverage.
- **Model far too conservative** (coverage ~100%, large overestimates) → you
  can lower `_CPU_EFF_BURST_WEIGHT`, but only with the cost gate in mind: the
  wall inflation feeds projected cost, so overestimating wall mainly *under*-
  states savings; it rarely produces bad recommendations. Bias conservative.

Also re-check the wave outcome wholesale while you have the data (this is the
go/no-go for promoting validations to prod):

- cost delta distribution (2026-06 baseline: median −35%),
- `val_mem_p95 > 82` → OOM-risk, exclude from promotion,
- wall regressions on DAGs with `schedule_interval ≤ 120 min` → SLA violations,
  must be reverted.

## Step 5 — Apply and verify

1. Edit the constants + their comment blocks in `scripts/recommend_cluster_specs.py`.
2. Run the unit suite (Python must be <3.13):
   `uv run --python 3.12 pytest tests/unit/scripts/test_recommend_cluster_specs.py -q`
3. If any `TestRealDagAcceptance` case fails, the change altered live-DAG
   decisions — verify each diff is sensible, then regenerate the expected
   blocks in `tests/fixtures/recommend_cluster_specs_acceptance.json` by
   rebuilding each `DagMetrics(**kwargs)` and re-dumping the `expected` fields
   (see the fixture's `regenerated` note for the convention).
4. Diff fleet impact old-vs-new on one metrics CSV:

   ```bash
   # one shared input
   uv run --no-project --with pandas python -c "
   import sys; sys.path.insert(0, '.')
   from scripts import recommend_cluster_specs as rcs
   open('/tmp/arm_metrics.sql','w').write(rcs.build_sql(days=14, min_days=3, min_runs=3))"
   # fetch /tmp/arm_metrics.csv via execute_trino.py (same flags as step 1)
   git stash  # or git show HEAD:scripts/recommend_cluster_specs.py > old.py
   uv run --no-project --with "pandas,pyyaml" python scripts/recommend_cluster_specs.py \
     --metrics-csv /tmp/arm_metrics.csv --out-dir /tmp/recs_old
   git stash pop
   uv run --no-project --with "pandas,pyyaml" python scripts/recommend_cluster_specs.py \
     --metrics-csv /tmp/arm_metrics.csv --out-dir /tmp/recs_new
   ```

   Compare cohort counts and projected savings; large unexplained swings mean
   stop and investigate before staging anything.
5. Update `docs/platform/cluster_spec_recommender_algorithm.md` (the sizer and
   SLA-guard sections quote the calibration numbers).
6. Stage the next validation wave with `--trino --validation-config` per
   `docs/platform/cluster_spec_recommender_runbook.md`.
