-- ============================================================================
-- dag_health.sql
--
-- Per-DAG rolling observability metrics computed daily over TWO trailing
-- windows simultaneously: 7 days and 28 days. One row per
-- (airflow_dag_id, dt_window_end). Reads exclusively from
-- dw_databricks_health.fact_databricks_task_run.
--
-- Wide-form schema: every metric column is duplicated as `<metric>_7d` and
-- `<metric>_28d`. Both windows share the same denominator data set (one read
-- of 28 days of fact rows) — the 7d aggregates are computed via FILTER
-- (WHERE in_7d_window) so the SQL stays a single SELECT.
--
-- Window choice rationale:
--   - 7d:  "act this sprint". A regression yesterday shows up immediately;
--          right-sizing decisions can be made before the 28d average shifts.
--   - 28d: matches the Databricks billing aggregation default; smooths
--          single-day spikes (Mondays, releases, ad-hoc backfills) for
--          steady-state cost monitoring.
--
-- Adding a 1d / 90d window later is mechanical: extend `window_runs` to
-- read N days, add an `in_<N>d_window` flag, and add `<metric>_<N>d`
-- columns alongside the existing pairs.
--
-- Grain: one row per (airflow_dag_id, dt_window_end). DAGs with zero runs
-- in the 28d window are NOT in the output (we GROUP BY observed
-- airflow_dag_ids only); a DAG that stops running disappears from this
-- table after 28 days.
--
-- Cost / cluster utilization metrics inherit the over-attribution caveat
-- from fact_databricks_task_run for shared interactive clusters — see the
-- fact's metadata. Most bietlejuice DAGs use job clusters where attribution
-- is 1:1.
--
-- The fact's stage-level columns are nullable (NULL when the Spark event
-- log hasn't landed yet, the task ran before PR 23078 enabled eventLog,
-- the task ran no Spark stages, OR `is_stage_attribution_ambiguous = true`).
-- Aggregations use SUM/AVG which silently skip NULLs;
-- `pct_runs_with_stage_data_<window>d` exposes how complete the underlying
-- data is for each DAG before drawing conclusions about spill / shuffle.
--
-- The fact's `*_script_seconds` and `*_overwatch_usd` columns are
-- cluster-day attributes — every task run on a (id_cluster, dt_task_started)
-- carries identical values. Aggregating those at the task-run grain over-counts
-- (mean is fine, SUM/percentiles are biased toward DAGs with many task runs per
-- cluster-day). We dedupe via `is_first_task_of_cluster_day` (computed below);
-- aggregations guard the column with `IF(is_first_task_of_cluster_day, …, NULL)`
-- so SUM/AVG/APPROX_PERCENTILE skip the duplicates.
-- ============================================================================
WITH window_runs AS (
    SELECT
        airflow_dag_id,
        dag_name,
        team_owner,
        cost_center,
        ecosystem,
        environment,
        provisioner,
        id_databricks_run,
        id_databricks_task_run,
        id_cluster,
        dt_task_started,
        ts_task_started,
        total_duration_seconds,
        execution_duration_seconds,
        setup_duration_seconds,
        init_script_seconds,
        cluster_startup_seconds,
        dbu_consumed,
        cost_usd_estimate,
        is_success,
        is_failed,
        is_pool_acquisition_slow,
        p95_driver_cpu_busy_percent,
        p95_worker_cpu_busy_percent,
        p95_driver_mem_used_percent,
        p95_worker_mem_used_percent,
        nvme_utilization_pct_p95,
        total_executor_run_time_ms,
        total_disk_bytes_spilled,
        total_memory_bytes_spilled,
        total_input_bytes_read,
        max_peak_execution_memory_bytes,
        max_jvm_heap_bytes,
        total_gc_time_ms,
        max_task_skew_ratio,
        total_shuffle_bytes_read,
        total_shuffle_bytes_written,
        has_stage_data,
        -- True only on the earliest task-run row for each (id_cluster, dt_task_started).
        -- Used to dedupe the cluster-day-grain init-script columns before aggregation.
        ROW_NUMBER() OVER (
            PARTITION BY id_cluster, dt_task_started
            ORDER BY ts_task_started, id_databricks_task_run
        ) = 1                                                          AS is_first_task_of_cluster_day,
        -- Boolean flag used as the FILTER predicate for 7d aggregates.
        -- Every row is in the 28d window by construction (WHERE clause below).
        dt_task_started >= DATE('{load_start_date}') - INTERVAL 6 DAYS AS in_7d_window
    FROM
        dw_databricks_health.fact_databricks_task_run
    WHERE
        dt_task_started >= DATE('{load_start_date}') - INTERVAL 27 DAYS
        AND dt_task_started <= DATE('{load_start_date}')
        AND airflow_dag_id IS NOT NULL
)
SELECT
    airflow_dag_id,
    DATE('{load_start_date}')                                                              AS dt_window_end,

    FIRST(dag_name)                                                                        AS dag_name,
    -- Governance / attribution dimensions, lifted unchanged from the fact.
    -- Expected to be 1:1 with airflow_dag_id; FIRST() makes that explicit
    -- and tolerates the rare cases where a DAG is re-tagged mid-window.
    FIRST(team_owner)                                                                      AS team_owner,
    FIRST(cost_center)                                                                     AS cost_center,
    FIRST(ecosystem)                                                                       AS ecosystem,
    FIRST(environment)                                                                     AS environment,
    FIRST(provisioner)                                                                     AS provisioner,

    -- ── Volume ──────────────────────────────────────────────────────────────
    COUNT(DISTINCT id_databricks_run)      FILTER (WHERE in_7d_window)                     AS total_runs_7d,
    COUNT(DISTINCT id_databricks_run)                                                      AS total_runs_28d,
    COUNT(DISTINCT id_databricks_task_run) FILTER (WHERE in_7d_window)                     AS total_task_runs_7d,
    COUNT(DISTINCT id_databricks_task_run)                                                 AS total_task_runs_28d,

    -- ── Cost ────────────────────────────────────────────────────────────────
    ROUND(SUM(dbu_consumed)      FILTER (WHERE in_7d_window), 4)                           AS total_dbu_consumed_7d,
    ROUND(SUM(dbu_consumed),                                  4)                           AS total_dbu_consumed_28d,
    ROUND(SUM(cost_usd_estimate) FILTER (WHERE in_7d_window), 4)                           AS total_cost_usd_7d,
    ROUND(SUM(cost_usd_estimate),                             4)                           AS total_cost_usd_28d,
    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_7d_window)
            / NULLIF(COUNT(DISTINCT IF(in_7d_window, id_databricks_run, NULL)), 0),
        4
    )                                                                                      AS avg_cost_usd_per_run_7d,
    ROUND(
        SUM(cost_usd_estimate) / NULLIF(COUNT(DISTINCT id_databricks_run), 0),
        4
    )                                                                                      AS avg_cost_usd_per_run_28d,

    -- ── Latency ─────────────────────────────────────────────────────────────
    ROUND(AVG(total_duration_seconds)     FILTER (WHERE in_7d_window), 2)                  AS avg_total_duration_seconds_7d,
    ROUND(AVG(total_duration_seconds),                                 2)                  AS avg_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.50) FILTER (WHERE in_7d_window)            AS p50_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.50)                                        AS p50_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.95) FILTER (WHERE in_7d_window)            AS p95_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.95)                                        AS p95_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.99) FILTER (WHERE in_7d_window)            AS p99_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.99)                                        AS p99_total_duration_seconds_28d,
    ROUND(AVG(execution_duration_seconds) FILTER (WHERE in_7d_window), 2)                  AS avg_execution_duration_seconds_7d,
    ROUND(AVG(execution_duration_seconds),                             2)                  AS avg_execution_duration_seconds_28d,
    ROUND(AVG(setup_duration_seconds)     FILTER (WHERE in_7d_window), 2)                  AS avg_setup_duration_seconds_7d,
    ROUND(AVG(setup_duration_seconds),                                 2)                  AS avg_setup_duration_seconds_28d,
    APPROX_PERCENTILE(setup_duration_seconds, 0.95) FILTER (WHERE in_7d_window)            AS p95_setup_duration_seconds_7d,
    APPROX_PERCENTILE(setup_duration_seconds, 0.95)                                        AS p95_setup_duration_seconds_28d,

    -- ── Init-script timing (cluster-day grain — deduped via is_first_task_of_cluster_day)
    -- "How long do init scripts cost this DAG?" Headline driver of the optimise-or-remove
    -- init-script workstream (DPLT-928). Mean across the bietlejuice fleet is ~95s with
    -- a long tail; sort by `total_init_minutes_28d DESC` to find optimisation targets.
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, init_script_seconds, NULL), 0.50)
        FILTER (WHERE in_7d_window)                                                        AS p50_init_script_seconds_7d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, init_script_seconds, NULL), 0.50)   AS p50_init_script_seconds_28d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, init_script_seconds, NULL), 0.95)
        FILTER (WHERE in_7d_window)                                                        AS p95_init_script_seconds_7d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, init_script_seconds, NULL), 0.95)   AS p95_init_script_seconds_28d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, init_script_seconds, NULL))
            FILTER (WHERE in_7d_window) / 60.0,
        2
    )                                                                                      AS total_init_minutes_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, init_script_seconds, NULL)) / 60.0,
        2
    )                                                                                      AS total_init_minutes_28d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, cluster_startup_seconds, NULL), 0.95)
        FILTER (WHERE in_7d_window)                                                        AS p95_cluster_startup_seconds_7d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, cluster_startup_seconds, NULL), 0.95) AS p95_cluster_startup_seconds_28d,

    -- ── Reliability ─────────────────────────────────────────────────────────
    SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window)                 AS failed_task_runs_7d,
    SUM(CASE WHEN is_failed THEN 1 ELSE 0 END)                                             AS failed_task_runs_28d,
    ROUND(
        SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                      AS error_rate_pct_7d,
    ROUND(SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2)     AS error_rate_pct_28d,
    SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window)  AS cold_start_count_7d,
    SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END)                              AS cold_start_count_28d,
    ROUND(
        SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                      AS cold_start_rate_pct_7d,
    ROUND(
        SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0),
        2
    )                                                                                      AS cold_start_rate_pct_28d,
    ROUND(SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) /  7.0, 2)  AS cold_starts_per_day_7d,
    ROUND(SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END)                            / 28.0, 2)  AS cold_starts_per_day_28d,

    -- ── Cluster utilization (averages of P95 daily values) ─────────────────
    ROUND(AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_7d_window), 2)                 AS avg_p95_driver_cpu_busy_percent_7d,
    ROUND(AVG(p95_driver_cpu_busy_percent),                             2)                 AS avg_p95_driver_cpu_busy_percent_28d,
    ROUND(AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_7d_window), 2)                 AS avg_p95_worker_cpu_busy_percent_7d,
    ROUND(AVG(p95_worker_cpu_busy_percent),                             2)                 AS avg_p95_worker_cpu_busy_percent_28d,
    ROUND(AVG(p95_driver_mem_used_percent) FILTER (WHERE in_7d_window), 2)                 AS avg_p95_driver_mem_used_percent_7d,
    ROUND(AVG(p95_driver_mem_used_percent),                             2)                 AS avg_p95_driver_mem_used_percent_28d,
    ROUND(AVG(p95_worker_mem_used_percent) FILTER (WHERE in_7d_window), 2)                 AS avg_p95_worker_mem_used_percent_7d,
    ROUND(AVG(p95_worker_mem_used_percent),                             2)                 AS avg_p95_worker_mem_used_percent_28d,
    ROUND(AVG(nvme_utilization_pct_p95)    FILTER (WHERE in_7d_window), 2)                 AS avg_nvme_utilization_pct_p95_7d,
    ROUND(AVG(nvme_utilization_pct_p95),                                2)                 AS avg_nvme_utilization_pct_p95_28d,

    -- ── Spark stage signals (require PR #23078) ─────────────────────────────
    SUM(total_disk_bytes_spilled)        FILTER (WHERE in_7d_window)                       AS total_disk_bytes_spilled_7d,
    SUM(total_disk_bytes_spilled)                                                          AS total_disk_bytes_spilled_28d,
    SUM(total_memory_bytes_spilled)      FILTER (WHERE in_7d_window)                       AS total_memory_bytes_spilled_7d,
    SUM(total_memory_bytes_spilled)                                                        AS total_memory_bytes_spilled_28d,
    MAX(max_peak_execution_memory_bytes) FILTER (WHERE in_7d_window)                       AS peak_execution_memory_bytes_7d,
    MAX(max_peak_execution_memory_bytes)                                                   AS peak_execution_memory_bytes_28d,
    MAX(max_jvm_heap_bytes)              FILTER (WHERE in_7d_window)                       AS peak_jvm_heap_bytes_7d,
    MAX(max_jvm_heap_bytes)                                                                AS peak_jvm_heap_bytes_28d,
    SUM(total_gc_time_ms)                FILTER (WHERE in_7d_window)                       AS total_gc_time_ms_7d,
    SUM(total_gc_time_ms)                                                                  AS total_gc_time_ms_28d,
    MAX(max_task_skew_ratio)             FILTER (WHERE in_7d_window)                       AS peak_task_skew_ratio_7d,
    MAX(max_task_skew_ratio)                                                               AS peak_task_skew_ratio_28d,
    SUM(total_shuffle_bytes_read)        FILTER (WHERE in_7d_window)                       AS total_shuffle_bytes_read_7d,
    SUM(total_shuffle_bytes_read)                                                          AS total_shuffle_bytes_read_28d,
    SUM(total_shuffle_bytes_written)     FILTER (WHERE in_7d_window)                       AS total_shuffle_bytes_written_7d,
    SUM(total_shuffle_bytes_written)                                                       AS total_shuffle_bytes_written_28d,

    -- ── Raw ratios (objective signals; thresholds for verdicts live in the
    --              dag_verdict view per DPLT-935, NOT here) ──────────────────
    -- Worker CPU utilisation: avg_p95_worker_cpu_busy_percent / 100.
    -- Values < 0.30 indicate consistently-cold workers (over-provisioned).
    ROUND(AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_7d_window) / 100.0, 4)         AS worker_cpu_utilization_ratio_7d,
    ROUND(AVG(p95_worker_cpu_busy_percent)                             / 100.0, 4)         AS worker_cpu_utilization_ratio_28d,
    -- Driver CPU utilisation: same thing for the driver. Useful with
    -- driver_minus_worker_cpu_pp to spot serial-driver bottlenecks.
    ROUND(AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_7d_window) / 100.0, 4)         AS driver_cpu_utilization_ratio_7d,
    ROUND(AVG(p95_driver_cpu_busy_percent)                             / 100.0, 4)         AS driver_cpu_utilization_ratio_28d,
    -- "Driver hot, workers cold" first-glance signal in percentage points.
    -- Positive ⇒ driver P95 CPU busy is higher than workers ⇒ likely a
    -- serial driver-side bottleneck (Python UDFs, .toPandas, big collect,
    -- schema evolution, etc.) and the worker shape is over-provisioned.
    ROUND(
        AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_7d_window)
            - AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_7d_window),
        2
    )                                                                                      AS driver_minus_worker_cpu_pp_7d,
    ROUND(
        AVG(p95_driver_cpu_busy_percent)
            - AVG(p95_worker_cpu_busy_percent),
        2
    )                                                                                      AS driver_minus_worker_cpu_pp_28d,
    -- Spill-to-input ratio: total_disk_bytes_spilled / total_input_bytes_read.
    -- High values ⇒ memory pressure (executors too small for working set).
    -- Use this instead of a strict heap-pressure ratio because we don't
    -- carry executor_memory_allocated_bytes on the fact today.
    ROUND(
        SUM(total_disk_bytes_spilled) FILTER (WHERE in_7d_window)
            / NULLIF(CAST(SUM(total_input_bytes_read) FILTER (WHERE in_7d_window) AS DOUBLE), 0),
        6
    )                                                                                      AS spill_to_input_ratio_7d,
    ROUND(
        SUM(total_disk_bytes_spilled)
            / NULLIF(CAST(SUM(total_input_bytes_read) AS DOUBLE), 0),
        6
    )                                                                                      AS spill_to_input_ratio_28d,
    -- Cost efficiency: total_cost_usd / executor-second. Lower ⇒ more useful
    -- compute per dollar. Tracks both cluster-shape efficiency AND scheduling
    -- (cold starts, retries inflate the denominator without inflating the
    -- numerator). NULL when stage data is unavailable / ambiguous.
    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_7d_window)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_7d_window) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                      AS cost_efficiency_usd_per_executor_second_7d,
    ROUND(
        SUM(cost_usd_estimate)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                      AS cost_efficiency_usd_per_executor_second_28d,

    -- ── DQ ──────────────────────────────────────────────────────────────────
    ROUND(
        SUM(CASE WHEN has_stage_data THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                      AS pct_runs_with_stage_data_7d,
    ROUND(SUM(CASE WHEN has_stage_data THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS pct_runs_with_stage_data_28d,

    CURRENT_TIMESTAMP()                                                                    AS ts_load,

    YEAR(DATE('{load_start_date}'))                                                        AS year,
    MONTH(DATE('{load_start_date}'))                                                       AS month,
    DAY(DATE('{load_start_date}'))                                                         AS day

FROM
    window_runs
GROUP BY
    airflow_dag_id
