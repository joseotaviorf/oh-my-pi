# Cluster right-sizing: feedback loop & next-generation telemetry plan

**Status:** implemented 2026-06-11 (D1–D3, C, B, A steps 1–3). Remaining:
D4 automation (recalibration sourcing from the outcomes table once it has
history) and A step 4 (autoscale cohort). Implementation:
`dags/platform/rightsizing_outcomes/` (D1),
`scripts/promote_rightsizing_validations.py` + ledger (D2/D3),
`scripts/recommend_cluster_specs.py` `--memory-history-csv` /
`--task-metrics-csv` / direct-jump worker resize with cores floor (B, A, C).
**Context:** the recommender (`scripts/recommend_cluster_specs.py`) is a static,
cost-truthful sizer calibrated on one validation wave. This plan closes its two
structural gaps — no post-decision feedback, and percentile-blended telemetry —
and speeds up convergence. Tracks are independent; D is the priority.

Related docs: `cluster_spec_recommender_algorithm.md` (current engine),
`cluster_recommender_recalibration_runbook.md` (manual calibration this plan
automates), `cluster_rightsizing_spark_review_backlog.md`.

---

## Track D — Closed feedback loop (priority)

Today the loop is: recommend → stage validation blocks → human eyeballs runs →
human promotes → recommender forgets. Each arrow is manual and lossy. Target:

```
recommend → validate → auto-compare → promote gate → post-promotion watch
     ↑                                                        │
     └──────────────── calibration table ←────────────────────┘
```

### D1. Outcomes table + monitoring DAG

New platform DAG (e.g. `dags/platform/rightsizing_outcomes/`, daily) writing
`enrich_rightsizing_outcomes` (one row per DAG per day per side):

- Join `fact_databricks_dag_run` prod vs `…__validation` twins (same join keys
  as the recalibration runbook SQL).
- Columns: run counts, avg cost, wall p50/p95, worker/driver cpu p50/p95,
  mem p95, failure counts, plus the *spec under test* (node types, count,
  engine) and the recommender metadata (cohort, predicted cost delta,
  predicted wall inflation) parsed from the `validation:` blocks in git.
- Predicted-vs-observed in one row is the calibration feed: the recalibration
  runbook's step 1–2 becomes a `SELECT`, and model drift (coverage of the wall
  model, cost-prediction error) becomes a chartable metric instead of a
  one-off study.
- Reuse the pass/warn/fail thresholds already implemented for
  `--validation-outcomes` in `recommend_cluster_specs.py` (cost ±15%/±30%,
  mem>82, wall vs cadence limit) — port them into the DAG's SQL or a small
  shared helper rather than reimplementing.

Standard checklist applies: `queries/`, `metadata/` with lineage, declaration,
`make create-dag-files`, dependencies file.

### D2. Promotion gate

Script (CI-runnable, e.g. `scripts/promote_rightsizing_validations.py`) that
reads the outcomes table and emits a promotion report + the cluster-file edits:

- **Promote** on the first clean signal — deliberately aggressive, because the
  post-promotion watch (D3) is the real safety net and validation slots are
  the scarce resource:
  - ≥1 successful validation run (ran to conclusion, no task/Databricks
    failure, no OOM),
  - cost below the prod baseline,
  - wall not much worse: ≤ ~1.5× prod wall p50 for unconstrained schedules,
    ≤ max(0.8×interval, prod wall p95) when the schedule interval ≤ 2h.
  One borderline guard: `val mem_p95 > 82` holds for one more run even when
  cost passed — OOM is the one failure D3 cannot cheaply revert its way out
  of mid-incident.
- **Reject** on failure/OOM or cost ≥ baseline → remove the validation block
  (`remove_validation_from_cluster_file` already exists) and record the
  outcome row as a negative calibration sample.
- **Extend** only while a DAG has zero completed validation runs, with an age
  cap (~2 weeks) after which the slot is freed.
- Output: a single PR's worth of changes — promoted specs moved from
  `validation.cluster` into the prod `cluster:` block, rejected blocks removed.
  Human review of the PR is the only manual step left.

### D3. Post-promotion watch

At promotion time, snapshot the pre-change baseline (cost/wall/mem percentiles
over the prior 14d) into the outcomes table. For 7 days after the prod change:

- Compare daily prod runs against the snapshot with the same thresholds.
- Regression (cost > baseline +15%, any OOM, cadence-SLA breach) → alert
  (Slack/Opsgenie, same channel as other platform DAG alerts) listing the
  revert: the snapshot row contains the exact previous spec.
- Clean pass after 7 days → experiment closed; rows remain as permanent
  calibration data.

### D4. Continuous recalibration

Quarterly (or on drift alert from D1's coverage metric): re-fit
`_CPU_EFF_BURST_WEIGHT` / wall-model `f` per
`cluster_recommender_recalibration_runbook.md`, now sourcing pairs from the
outcomes table instead of ad-hoc SQL. The runbook stays the procedure; this
plan only changes where the data comes from.

---

## Track A — Task-level telemetry in the recommendation engine

**Decision: task_run should be a first-class input to the recommender — but
only its health-percentile and timeline columns.**
Lineage (see `dags/platform/dw_databricks_health/queries/dw/fact_databricks_task_run.sql`):
task_run = `system.lakeflow.job_task_run_timeline` spine + billing (negotiated
DBU, wall-clock-share attribution) + `system.compute.clusters` spec +
`daily_cluster_health` P50/P95 utilization + `spark_stage_metrics` parsed from
event logs. `fact_databricks_dag_run` is the task-duration-weighted rollup —
the percentile blending that forced the engine onto priors happens exactly at
that aggregation step.

**Coverage reality check (2026-06-11):** the stage-derived columns
(`total_executor_cpu_time_ms`, `max_task_skew_ratio`, spill bytes,
`max_jvm_heap_bytes`, `total_input_bytes_read`) are **~0% populated** (0.0%
every month Jan–Jun 2026 except a 1.15% blip in May, over ~8M task runs).
Treat them as opportunistic enrichment — use when present, NEVER as a
load-bearing input. The usable signal is: per-task `p50/p95`
cpu-busy/cpu-wait/mem percentiles (73–78% of task runs), task durations,
`peak_concurrent_workers`, per-task result state, and the spine timing
columns (~complete). Fixing the `spark_stage_metrics` ingestion (event-log
parsing coverage) is a separate prerequisite project if measured executor CPU
time is ever wanted; nothing below depends on it.

What the reliable columns still buy over the dag_run blend:

1. **Memory sizing on the critical task, not the blend.** Size memory off
   `max over tasks(p95_worker_mem_used_percent / p95_driver_mem_used_percent)`.
   The dag_run duration-weighted average dilutes a short memory-hungry task
   behind long cheap ones — the exact OOM-risk shape. This is the single
   biggest fidelity win available from task_run, and it needs only the
   73–78%-covered health percentiles.
2. **Phase structure from per-task percentiles + durations.** Each Airflow
   task is a phase. A DAG whose tasks bimodally split into low-CPU/high-wait
   tasks and high-CPU tasks is the scan-then-compute shape → recommend
   **autoscale bounds** (min sized for the compute tasks' demand, max for the
   scan tasks') instead of a fixed shrink. New cohort, replaces today's
   `autoscale_review` dead end for these DAGs.
3. **A better wall-model `f` without stage metrics.** Duration-weighted
   per-task `p50_worker_cpu_busy` over only the tasks a candidate actually
   constrains is a sharper duty-cycle estimate than the dag-level blend, and
   `peak_concurrent_workers` (spine-derived, reliable) corrects the
   denominator for autoscaling DAGs where provisioned cores ≠ worker_count.
4. **Review flags that name the offending task.** High
   `p95_worker_cpu_wait_percent` + low `p50_worker_cpu_busy_percent`
   concentrated in one task pinpoints *which* query needs the io_scan fix —
   the backlog doc gets a task id instead of a code-reading session.
5. **Opportunistic stage enrichment (when present only).** If a DAG happens to
   have stage rows: `f_true` cross-check, skew → shuffle_skew flag, spill →
   NVMe gate. Display-only / tie-breaker; never gates a decision, never
   imputed when absent.

### Integration plan

1. **Second query, not a bigger one.** Add `build_task_sql()` next to
   `build_sql()`: per (dag_id, airflow_task_id) over the window — run counts,
   wall p50/p95, cpu/mem/wait p50/p95, `f_true`, spill totals,
   `max_task_skew_ratio`, `max_jvm_heap_bytes`, `total_input_bytes_read`,
   `is_stage_attribution_ambiguous` share, `peak_concurrent_workers`.
   Filter `NOT is_job_on_interactive`, successful states only, and require
   per-task health-percentile presence (drop rows without them rather than
   imputing). Loaded into a `dict[dag_id, list[TaskMetrics]]` beside
   `DagMetrics` — cohort/cost logic keeps consuming `DagMetrics`; task data
   refines demand and flags. A DAG whose tasks lack percentile coverage falls
   back to the dag_run path wholesale.
2. **Sizing on the critical task, not the blend.** `_additive_memory_gb` takes
   `max over tasks(p95 mem)`; CPU demand takes `max over tasks(cpu_eff)`;
   wall-model `f` becomes the duration-weighted per-task p50-busy duty cycle
   with the `peak_concurrent_workers` denominator correction. Keep the
   current dag_run path as fallback when task rows are missing/ambiguous.
3. **Task-resolved flags.** `io_scan_review` → the specific task(s) with high
   wait + low cpu (named in the backlog doc, skipping the code-reading step).
   Skew/spill-based flags only opportunistically, per the coverage caveat.
4. **Autoscale cohort.** Bimodal task split (low-CPU/high-wait vs high-CPU
   tasks) → recommend `min/max_autoscale_workers` instead of a fixed shrink.
5. **Validation of the upgrade itself**: before switching sizing over, run
   both demand models on the fleet and diff — `f_true` vs p50-busy fleet-wide,
   and per-DAG demand deltas. Large disagreements are the interesting cases;
   inspect a sample before trusting either.

### Known caveats (from the SQL)

- **Stage-derived columns are ~0% populated** (see coverage check above) —
  opportunistic only. When present, `is_stage_attribution_ambiguous` (parallel
  `execute-job-cluster-N` tasks sharing a spark_app) additionally invalidates
  them per-DAG.
- **Health percentiles cover ~74% of task runs**: require presence, fall back
  to dag_run per-DAG, never impute.
- **Multiple clusters per logical DAG execution** (parallel jobs): all share
  one `*_cluster.yml` spec, so per-task demand still maps to one recommended
  shape — size for the max-demand task/cluster.
- DBU attribution to tasks is wall-clock-share, hour-bucketed at source — fine
  for per-DAG costing, do not over-interpret per-task cost.

## Track B — Long memory lookback via AMD history

Memory is the only fatal mistake, and 14 ARM days miss monthly seasonality.
The AMD (pre-Graviton) history is valid signal for memory *footprint*:

- Convert to absolute GB: `pct × node_memory_gb` per run, both architectures
  (`--use-amd-history` plumbing and the AMD SQL already exist).
- Size memory against `max(p95_GB over 14d ARM, p99_GB over 90d ARM+AMD)`.
- Keep CPU/wall on the recent ARM window (AMD CPU telemetry is biased by the
  arch change; `AMD_WALL_CORRECTION` exists but is fleet-median, not per-DAG).
- Cheap: one extra query + a max() in `_additive_memory_gb`'s input.

## Track C — Convergence

With the cost gate, the work-conserving wall model, and (after Track D) auto
revert in place, conservatism in *step size* costs months:

- Remove the “−2 workers per cycle” cap in `_worker_resize`: jump straight to
  the demand-derived count (floor 2). The wall model already prices the jump;
  validation catches errors; D3 reverts mistakes.
- Keep one guard: a single recommendation may not cut total cores below
  `f_true × old_cores / 0.85` (i.e. never below measured demand + headroom).
- Re-run cadence: weekly recommender runs; with D2's ~1-week promotion cycle a
  grossly oversized DAG converges in 1–2 cycles instead of 4+.

---

## Sequencing

1. **D1 + D2** (outcomes table, single-clean-run promotion gate) — unblocks
   everything, uses only existing telemetry. D3 (post-promotion watch) ships
   with them: aggressive promotion is only safe with the watch in place.
2. **C** (step-size removal) — trivial once D3 exists; large savings pull-in.
3. **A steps 1–3** (task query + critical-task sizing + measured flags) —
   engine fidelity; step 5's fleet diff gates the switch-over.
4. **B** (long memory lookback) — insurance, cheap, anytime.
5. **A step 4** (autoscale cohort) — biggest design change, do last with the
   most calibration data in hand.
