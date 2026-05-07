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
-- Grain: one row per (airflow_dag_id, dt_window_end). DAGs with zero runs
-- in the 28d window are NOT in the output (we GROUP BY observed
-- airflow_dag_ids only); a DAG that stops running disappears from this
-- table after 28 days.
--
-- Volume columns:
--   total_dag_runs_*  — COUNT(DISTINCT date_trunc('MINUTE', ts_run_started)):
--       approximate Airflow DAG executions (parallel jobs in the same minute
--       collapse to one; intraday schedules keep distinct minutes).
--   total_job_runs_*  — COUNT(DISTINCT id_databricks_run) Databricks jobs.
--   total_task_runs_* — COUNT(DISTINCT id_databricks_task_run).
--
-- Cost: cluster-day Overwatch USD columns must be deduped with
-- `is_first_task_of_cluster_day`. Calculated EC2 (`total_ec2_cost_calculated_usd`)
-- uses the same dedupe. `total_cost_usd` = SUM(DBU USD) + SUM(deduped calculated EC2 USD).
-- ============================================================================
WITH window_runs AS (
    SELECT
        airflow_dag_id,
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
        ts_run_started,
        total_duration_seconds,
        execution_duration_seconds,
        setup_duration_seconds,
        init_script_seconds,
        cluster_startup_seconds,
        dbu_consumed,
        cost_usd_estimate,
        total_ec2_cost_calculated_usd,
        spot_hours,
        on_demand_hours,
        total_cost_usd,
        total_cost_overwatch_usd,
        total_ec2_cost_overwatch_usd,
        total_dbu_cost_overwatch_usd,
        is_success,
        is_failed,
        is_pool_acquisition_slow,
        p95_driver_cpu_busy_percent,
        p95_worker_cpu_busy_percent,
        p95_driver_mem_used_percent,
        p95_worker_mem_used_percent,
        local_disk_utilization_pct_p95,
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
        ROW_NUMBER() OVER (
            PARTITION BY id_cluster, dt_task_started
            ORDER BY ts_task_started, id_databricks_task_run
        ) = 1                                                          AS is_first_task_of_cluster_day,
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
    FIRST(team_owner)                                                                      AS team_owner,
    FIRST(cost_center)                                                                     AS cost_center,
    FIRST(ecosystem)                                                                       AS ecosystem,
    FIRST(environment)                                                                     AS environment,
    FIRST(provisioner)                                                                     AS provisioner,

    COUNT(DISTINCT date_trunc('MINUTE', ts_run_started)) FILTER (WHERE in_7d_window)       AS total_dag_runs_7d,
    COUNT(DISTINCT date_trunc('MINUTE', ts_run_started))                                   AS total_dag_runs_28d,
    COUNT(DISTINCT id_databricks_run)      FILTER (WHERE in_7d_window)                     AS total_job_runs_7d,
    COUNT(DISTINCT id_databricks_run)                                                    AS total_job_runs_28d,
    COUNT(DISTINCT id_databricks_task_run) FILTER (WHERE in_7d_window)                   AS total_task_runs_7d,
    COUNT(DISTINCT id_databricks_task_run)                                               AS total_task_runs_28d,

    ROUND(SUM(dbu_consumed)      FILTER (WHERE in_7d_window), 4)                           AS total_dbu_consumed_7d,
    ROUND(SUM(dbu_consumed),                                  4)                         AS total_dbu_consumed_28d,
    ROUND(SUM(cost_usd_estimate) FILTER (WHERE in_7d_window), 4)                       AS total_dbu_cost_usd_7d,
    ROUND(SUM(cost_usd_estimate),                             4)                         AS total_dbu_cost_usd_28d,
    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_7d_window)
            / NULLIF(COUNT(DISTINCT IF(in_7d_window, date_trunc('MINUTE', ts_run_started), NULL)), 0),
        4
    )                                                                                    AS avg_dbu_cost_usd_per_dag_run_7d,
    ROUND(
        SUM(cost_usd_estimate) / NULLIF(COUNT(DISTINCT date_trunc('MINUTE', ts_run_started)), 0),
        4
    )                                                                                    AS avg_dbu_cost_usd_per_dag_run_28d,

    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_calculated_usd, NULL))
            FILTER (WHERE in_7d_window),
        4
    )                                                                                    AS total_ec2_cost_calculated_usd_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_calculated_usd, NULL)),
        4
    )                                                                                    AS total_ec2_cost_calculated_usd_28d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, spot_hours, NULL))
            FILTER (WHERE in_7d_window),
        4
    )                                                                                    AS spot_hours_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, spot_hours, NULL)),
        4
    )                                                                                    AS spot_hours_28d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, on_demand_hours, NULL))
            FILTER (WHERE in_7d_window),
        4
    )                                                                                    AS on_demand_hours_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, on_demand_hours, NULL)),
        4
    )                                                                                    AS on_demand_hours_28d,

    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_7d_window)
            + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_calculated_usd, NULL))
                FILTER (WHERE in_7d_window),
        4
    )                                                                                    AS total_cost_usd_7d,
    ROUND(
        SUM(cost_usd_estimate)
            + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_calculated_usd, NULL)),
        4
    )                                                                                    AS total_cost_usd_28d,
    ROUND(
        (
            SUM(cost_usd_estimate) FILTER (WHERE in_7d_window)
                + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_calculated_usd, NULL))
                    FILTER (WHERE in_7d_window)
        )
            / NULLIF(COUNT(DISTINCT IF(in_7d_window, date_trunc('MINUTE', ts_run_started), NULL)), 0),
        4
    )                                                                                    AS avg_total_cost_usd_per_dag_run_7d,
    ROUND(
        (
            SUM(cost_usd_estimate)
                + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_calculated_usd, NULL))
        )
            / NULLIF(COUNT(DISTINCT date_trunc('MINUTE', ts_run_started)), 0),
        4
    )                                                                                    AS avg_total_cost_usd_per_dag_run_28d,

    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_7d_window)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_7d_window) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                    AS cost_efficiency_usd_per_executor_second_7d,
    ROUND(
        SUM(cost_usd_estimate)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                    AS cost_efficiency_usd_per_executor_second_28d,

    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL))
            FILTER (WHERE in_7d_window),
        4
    )                                                                                    AS total_ec2_cost_overwatch_usd_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)),
        4
    )                                                                                    AS total_ec2_cost_overwatch_usd_28d,

    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_dbu_cost_overwatch_usd, NULL))
            FILTER (WHERE in_7d_window),
        4
    )                                                                                    AS total_dbu_cost_overwatch_usd_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_dbu_cost_overwatch_usd, NULL)),
        4
    )                                                                                    AS total_dbu_cost_overwatch_usd_28d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_cost_overwatch_usd, NULL))
            FILTER (WHERE in_7d_window),
        4
    )                                                                                    AS total_cost_overwatch_usd_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_cost_overwatch_usd, NULL)),
        4
    )                                                                                    AS total_cost_overwatch_usd_28d,

    ROUND(AVG(total_duration_seconds)     FILTER (WHERE in_7d_window), 2)               AS avg_total_duration_seconds_7d,
    ROUND(AVG(total_duration_seconds),                                 2)                 AS avg_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.50) FILTER (WHERE in_7d_window)          AS p50_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.50)                                      AS p50_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.95) FILTER (WHERE in_7d_window)          AS p95_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.95)                                      AS p95_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.99) FILTER (WHERE in_7d_window)          AS p99_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.99)                                      AS p99_total_duration_seconds_28d,
    ROUND(AVG(execution_duration_seconds) FILTER (WHERE in_7d_window), 2)              AS avg_execution_duration_seconds_7d,
    ROUND(AVG(execution_duration_seconds),                             2)               AS avg_execution_duration_seconds_28d,
    ROUND(AVG(setup_duration_seconds)     FILTER (WHERE in_7d_window), 2)               AS avg_setup_duration_seconds_7d,
    ROUND(AVG(setup_duration_seconds),                                 2)               AS avg_setup_duration_seconds_28d,
    APPROX_PERCENTILE(setup_duration_seconds, 0.95) FILTER (WHERE in_7d_window)            AS p95_setup_duration_seconds_7d,
    APPROX_PERCENTILE(setup_duration_seconds, 0.95)                                      AS p95_setup_duration_seconds_28d,

    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, init_script_seconds, NULL), 0.50)
        FILTER (WHERE in_7d_window)                                                      AS p50_init_script_seconds_7d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, init_script_seconds, NULL), 0.50)   AS p50_init_script_seconds_28d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, init_script_seconds, NULL), 0.95)
        FILTER (WHERE in_7d_window)                                                      AS p95_init_script_seconds_7d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, init_script_seconds, NULL), 0.95)   AS p95_init_script_seconds_28d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, init_script_seconds, NULL))
            FILTER (WHERE in_7d_window) / 60.0,
        2
    )                                                                                    AS total_init_minutes_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, init_script_seconds, NULL)) / 60.0,
        2
    )                                                                                    AS total_init_minutes_28d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, cluster_startup_seconds, NULL), 0.95)
        FILTER (WHERE in_7d_window)                                                      AS p95_cluster_startup_seconds_7d,
    APPROX_PERCENTILE(IF(is_first_task_of_cluster_day, cluster_startup_seconds, NULL), 0.95)
                                                                                         AS p95_cluster_startup_seconds_28d,

    ROUND(AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_7d_window), 2)             AS avg_p95_driver_cpu_busy_percent_7d,
    ROUND(AVG(p95_driver_cpu_busy_percent),                             2)             AS avg_p95_driver_cpu_busy_percent_28d,
    ROUND(AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_7d_window), 2)             AS avg_p95_worker_cpu_busy_percent_7d,
    ROUND(AVG(p95_worker_cpu_busy_percent),                             2)             AS avg_p95_worker_cpu_busy_percent_28d,
    ROUND(AVG(p95_driver_mem_used_percent) FILTER (WHERE in_7d_window), 2)             AS avg_p95_driver_mem_used_percent_7d,
    ROUND(AVG(p95_driver_mem_used_percent),                             2)             AS avg_p95_driver_mem_used_percent_28d,
    ROUND(AVG(p95_worker_mem_used_percent) FILTER (WHERE in_7d_window), 2)             AS avg_p95_worker_mem_used_percent_7d,
    ROUND(AVG(p95_worker_mem_used_percent),                             2)             AS avg_p95_worker_mem_used_percent_28d,
    ROUND(AVG(local_disk_utilization_pct_p95) FILTER (WHERE in_7d_window), 2)           AS avg_local_disk_utilization_pct_p95_7d,
    ROUND(AVG(local_disk_utilization_pct_p95),                         2)             AS avg_local_disk_utilization_pct_p95_28d,

    ROUND(
        AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_7d_window)
            - AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_7d_window),
        2
    )                                                                                    AS driver_minus_worker_cpu_pp_7d,
    ROUND(
        AVG(p95_driver_cpu_busy_percent)
            - AVG(p95_worker_cpu_busy_percent),
        2
    )                                                                                    AS driver_minus_worker_cpu_pp_28d,
    ROUND(
        SUM(total_disk_bytes_spilled) FILTER (WHERE in_7d_window)
            / NULLIF(CAST(SUM(total_input_bytes_read) FILTER (WHERE in_7d_window) AS DOUBLE), 0),
        6
    )                                                                                    AS spill_to_input_ratio_7d,
    ROUND(
        SUM(total_disk_bytes_spilled)
            / NULLIF(CAST(SUM(total_input_bytes_read) AS DOUBLE), 0),
        6
    )                                                                                    AS spill_to_input_ratio_28d,
    ROUND(AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_7d_window) / 100.0, 4)     AS worker_cpu_utilization_ratio_7d,
    ROUND(AVG(p95_worker_cpu_busy_percent)                             / 100.0, 4)     AS worker_cpu_utilization_ratio_28d,
    ROUND(AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_7d_window) / 100.0, 4)     AS driver_cpu_utilization_ratio_7d,
    ROUND(AVG(p95_driver_cpu_busy_percent)                             / 100.0, 4)     AS driver_cpu_utilization_ratio_28d,

    SUM(total_disk_bytes_spilled)        FILTER (WHERE in_7d_window)                   AS total_disk_bytes_spilled_7d,
    SUM(total_disk_bytes_spilled)                                                      AS total_disk_bytes_spilled_28d,
    SUM(total_memory_bytes_spilled)      FILTER (WHERE in_7d_window)                   AS total_memory_bytes_spilled_7d,
    SUM(total_memory_bytes_spilled)                                                    AS total_memory_bytes_spilled_28d,
    MAX(max_peak_execution_memory_bytes) FILTER (WHERE in_7d_window)                   AS peak_execution_memory_bytes_7d,
    MAX(max_peak_execution_memory_bytes)                                               AS peak_execution_memory_bytes_28d,
    MAX(max_jvm_heap_bytes)              FILTER (WHERE in_7d_window)                   AS peak_jvm_heap_bytes_7d,
    MAX(max_jvm_heap_bytes)                                                            AS peak_jvm_heap_bytes_28d,
    SUM(total_gc_time_ms)                FILTER (WHERE in_7d_window)                   AS total_gc_time_ms_7d,
    SUM(total_gc_time_ms)                                                              AS total_gc_time_ms_28d,
    MAX(max_task_skew_ratio)             FILTER (WHERE in_7d_window)                   AS peak_task_skew_ratio_7d,
    MAX(max_task_skew_ratio)                                                           AS peak_task_skew_ratio_28d,
    SUM(total_shuffle_bytes_read)        FILTER (WHERE in_7d_window)                   AS total_shuffle_bytes_read_7d,
    SUM(total_shuffle_bytes_read)                                                      AS total_shuffle_bytes_read_28d,
    SUM(total_shuffle_bytes_written)     FILTER (WHERE in_7d_window)                   AS total_shuffle_bytes_written_7d,
    SUM(total_shuffle_bytes_written)                                                   AS total_shuffle_bytes_written_28d,

    SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window)             AS failed_task_runs_7d,
    SUM(CASE WHEN is_failed THEN 1 ELSE 0 END)                                         AS failed_task_runs_28d,
    ROUND(
        SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS error_rate_pct_7d,
    ROUND(SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS error_rate_pct_28d,
    SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) AS cold_start_count_7d,
    SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END)                          AS cold_start_count_28d,
    ROUND(
        SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS cold_start_rate_pct_7d,
    ROUND(
        SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0),
        2
    )                                                                                    AS cold_start_rate_pct_28d,
    ROUND(SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) / 7.0, 2) AS cold_starts_per_day_7d,
    ROUND(SUM(CASE WHEN is_pool_acquisition_slow THEN 1 ELSE 0 END) / 28.0, 2)        AS cold_starts_per_day_28d,

    ROUND(
        SUM(CASE WHEN has_stage_data THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS pct_task_runs_with_stage_data_7d,
    ROUND(SUM(CASE WHEN has_stage_data THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2)
                                                                                         AS pct_task_runs_with_stage_data_28d,

    DATE('{load_start_date}')                                                          AS dt_window_end,
    CURRENT_TIMESTAMP()                                                                  AS ts_load,
    YEAR(DATE('{load_start_date}'))                                                    AS year,
    MONTH(DATE('{load_start_date}'))                                                   AS month,
    DAY(DATE('{load_start_date}'))                                                     AS day

FROM
    window_runs
GROUP BY
    airflow_dag_id
