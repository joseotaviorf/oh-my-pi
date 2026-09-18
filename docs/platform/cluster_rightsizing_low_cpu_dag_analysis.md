# Analyzing low-p50-CPU DAGs (Spark-review backlog playbook)

**Audience:** an agent (or engineer) picking up the backlog in
`docs/platform/cluster_rightsizing_spark_review_backlog.md` with no prior
context.
**Goal:** for a DAG flagged `io_scan_review` or `driver_bound_review`, determine
*why* its workers sit at low CPU, classify it with a verdict, and identify the
Spark-job/SQL-level fix. Right-sizing alone does not fix these — the cluster
is being wasted by the job's shape.

## Where the candidates come from

`scripts/recommend_cluster_specs.py` emits a `review_flags` column in
`recommendations.csv`:

| Flag | Trigger (multi-node only) | Prior |
| --- | --- | --- |
| `io_scan_review` | `wrk_wait_p95 > 40` and `wrk_cpu_p50 < 25` | workers wait on I/O |
| `driver_bound_review` | `wrk_wait_p95 < 10` and `wrk_cpu_p50 < 5` | driver does the work, workers idle |

The discriminator that matters: **near-zero IO-wait + low p50 is NOT an S3
scan** — it is API/driver-bound. **High IO-wait + low p50** is a scan or
shuffle-amplification problem. Verify against fresh telemetry in
`dw_databricks_health.fact_databricks_dag_run`
(columns `weighted_avg_p50_worker_cpu_busy_percent`,
`weighted_avg_p95_worker_cpu_busy_percent`,
`weighted_avg_p95_worker_cpu_wait_percent`) — flags in an old CSV may be stale.

## How to analyze one DAG

1. **Find the folder**: search `dags/` for `<dag_name>_declaration.yml`; the
   folder contains `queries/<layer>/*.sql`, optional `spark_jobs/*.py`,
   `*_cluster.yml`, `metadata/`.
2. **Read the cluster file**: note node types, worker count, `runtime_engine`
   (Photon?), NVMe (`*gd.*` nodes), autoscale.
3. **Read the SQL/spark jobs and answer, in order**:
   - *What are the inputs?* Delta tables, raw S3 JSON/CSV/gzip landing, JDBC,
     REST APIs? Wildcard paths? `dbutils.fs.ls` / boto3 listings?
   - *Is partition pruning effective?* Compare the input tables' partition
     columns (their `metadata/` or upstream declaration) against the query's
     WHERE clause. Classic miss: table partitioned `year/month/day/hour`,
     query filters `MAKE_DATE(year, month, day)` only → every hour partition
     of the day is read.
   - *Small files?* Upstream table with `run_optimize: false`, raw landing of
     many small JSON/gzip files, per-file read loops.
   - *Shuffle/skew?* Window functions for dedup, non-equi/inequality joins,
     `partitionBy` on high-cardinality skewed columns (e.g. `event_type`).
   - *Driver-only work?* REST pagination loops, `ThreadPoolExecutor` on the
     driver, rate-limit sleeps, `collect()`-then-process patterns, many small
     tables loaded serially on one cluster.
4. **Assign a verdict** (one line):
   - `io_scan` — small-file S3/listing reads or unpruned partition scans
     dominate; sub-tag the fix: *partition pruning*, *upstream compaction*,
     *ingestion batching*.
   - `shuffle_skew` — wait comes from shuffle over many/skewed partitions.
   - `driver_bound` — workers idle while the driver paginates/collects;
     the fix is shape-in-kind (single node, or move extraction off Spark).
   - `cpu_ok` — bursty but healthy (pure SQL with window/join bursts); no
     job-level action, the recommender's `cpu_eff` sizing handles it.
   - `unclear` — say what's missing.
5. **Record it** in the "Deep-dive verdicts" table of
   `cluster_rightsizing_spark_review_backlog.md`, with the evidence.

Delegate step 1–4 per DAG to read-only subagents in parallel when working a
batch — the analysis is independent per DAG.

## Worked examples (2026-06-11, verified by code inspection)

Telemetry given as `p50 / p95 / IO-wait p95` worker CPU.

- **langfuse** (9.8 / 88 / 12.6) → `io_scan` (ingestion batching). boto3
  recursively lists the whole Langfuse export bucket, regex-filters hourly
  windows, then `spark.read.json(file_list)` over many small JSON files; a
  driver-side REST enrichment with rate-limit sleeps adds dead time. Note the
  *low* IO-wait despite being a scan problem: listing+HTTP wait shows up as
  idle, not disk-wait — telemetry priors are priors, the code decides.
- **house_listing_search** (15.8 / 70 / 69) → `io_scan` (CDC landing). Shared
  `load_cdc_*.py` jobs `dbutils.fs.ls`-walk per-day gzip-JSON Debezium landing
  and write 4-level (y/m/d/h) partitions, 7 tables × 3 layers serially on one
  cluster.
- **enrich_search** (17.9 / 76 / 67) → `io_scan` (upstream compaction).
  Upstream `amplitude_subpartitioned` has `run_optimize: false` on the search
  event tables → many small Parquet files; full daily rebuild scans multiple
  years with only `year >= 2021` pruning; 14-day inequality-window joins.
  Photon ON — suspected to act as an S3-download accelerator (~3× DBU) rather
  than a query-engine win; validate dropping it via a shadow run.
- **dw_repairs** (9.8 / 80 / 65) → `io_scan` (partition pruning). Unpruned
  scans of y/m/d-partitioned `fact_ticket_events`; full scan of
  `ticket_comments`; 6+ window dedups.
- **greenhouse_v3** (2.2 / 55 / 1.2) → `driver_bound`. The driver serially
  paginates the Greenhouse Harvest REST API across ~27 tables while
  3× r6g.4xlarge workers idle; the p95 spike is the final JSON
  materialization burst. Near-zero IO-wait is the tell.
- **enrich_visit** (3.7 / 66 / 5.4) → `cpu_ok`. Pure Delta SQL; window
  functions and non-equi joins cause the bursts. No pathology.
- **dw_listing** (4.8 / 99 / 6) → `cpu_ok`. Pure Delta SQL, wide joins; Photon
  ON. Bursty but healthy.

## Fix playbook by verdict

| Verdict | Fix | Example |
| --- | --- | --- |
| io_scan / pruning | Add the missing partition predicates (`hour`, full y/m/d) to the SQL | dw_repairs |
| io_scan / compaction | Enable `run_optimize` (or scheduled OPTIMIZE) on the upstream table | enrich_search ← amplitude_subpartitioned |
| io_scan / batching | Replace per-file listing+read loops with coarser reads or pre-compacted landing | langfuse, house_listing_search |
| shuffle_skew | AQE skew-join handling / repartition before the skewed `partitionBy`; NVMe does **not** help unless `total_disk_bytes_spilled > 0` | amplitude_new (~20k skewed `event_type` partitions) |
| driver_bound | Collapse to single node (recommender proposes it), or move extraction off Spark to a plain Python task | greenhouse_v3 |
| cpu_ok | Nothing — `cpu_eff` sizing already right-sizes it | enrich_visit, dw_listing |

After any fix, validate via a shadow (validation-mode) run before touching the
prod spec, then let the recommender re-evaluate the DAG on the next cycle —
constraints and validation mechanics per
`docs/platform/cluster_spec_recommender_runbook.md`.
