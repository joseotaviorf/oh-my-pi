-- ============================================================================
-- fact_databricks_dag_run.sql
--
-- Logical Airflow DAG execution grain. One row per
-- (id_databricks_workspace, airflow_dag_id, ts_logical_run_started), where
-- ts_logical_run_started = date_trunc('MINUTE', ts_run_started).
--
-- Runs after `fact_databricks_task_run` via `inner_dependencies` in
-- dw_databricks_health_declaration.yml (alphabetical DAG task order alone would
-- run this table before the task fact).
--
-- Parallel Databricks jobs in the same minute collapse to one row; costs sum.
-- P95 cluster metrics are weighted by execution_duration_seconds across tasks.
--
-- Source: dw_databricks_health.fact_databricks_task_run.
-- ============================================================================
SELECT
    XXHASH64(
        CAST(ftr.id_databricks_workspace AS STRING),
        ftr.airflow_dag_id,
        CAST(UNIX_TIMESTAMP(date_trunc('MINUTE', ftr.ts_run_started)) AS STRING)
    )                                                             AS sk_databricks_dag_run,
    ftr.id_databricks_workspace,
    ftr.airflow_dag_id,
    date_trunc('MINUTE', ftr.ts_run_started)                     AS ts_logical_run_started,
    CAST(DATE_FORMAT(DATE(date_trunc('MINUTE', ftr.ts_run_started)), 'yyyyMMdd') AS INT)
                                                                  AS sk_dag_run_started_date,

    FIRST(ftr.team_owner     IGNORE NULLS)                        AS team_owner,
    FIRST(ftr.cost_center    IGNORE NULLS)                        AS cost_center,
    FIRST(ftr.ecosystem      IGNORE NULLS)                        AS ecosystem,
    FIRST(ftr.environment    IGNORE NULLS)                        AS environment,
    FIRST(ftr.provisioner    IGNORE NULLS)                        AS provisioner,

    COUNT(DISTINCT ftr.id_databricks_run)                           AS n_databricks_job_runs,
    COUNT(*)                                                        AS n_task_runs,
    SUM(CASE WHEN ftr.is_failed THEN 1 ELSE 0 END)                  AS n_failed_task_runs,
    SUM(CASE WHEN ftr.has_stage_data THEN 1 ELSE 0 END)             AS n_task_runs_with_stage_data,

    CAST(
        ROUND(SUM(ftr.total_dbu_consumed), 4) AS DECIMAL(25, 4)
    )                                                               AS total_dbu_consumed,
    CAST(
        ROUND(SUM(ftr.total_dbu_cost_usd), 4) AS DECIMAL(37, 4)
    )                                                               AS total_dbu_cost_usd,
    CAST(
        ROUND(SUM(ftr.total_ec2_cost_calculated_usd), 4) AS DECIMAL(38, 4)
    )                                                               AS total_ec2_cost_calculated_usd,
    CAST(
        ROUND(SUM(ftr.spot_hours), 4) AS DECIMAL(38, 4)
    )                                                               AS spot_hours,
    CAST(
        ROUND(SUM(ftr.on_demand_hours), 4) AS DECIMAL(38, 4)
    )                                                               AS on_demand_hours,
    CAST(
        ROUND(SUM(ftr.total_ec2_cost_overwatch_usd), 4) AS DECIMAL(38, 4)
    )                                                               AS total_ec2_cost_overwatch_usd,
    CAST(
        ROUND(SUM(ftr.total_dbu_cost_overwatch_usd), 4) AS DECIMAL(38, 4)
    )                                                               AS total_dbu_cost_overwatch_usd,
    CAST(
        ROUND(SUM(ftr.total_cost_overwatch_usd), 4) AS DECIMAL(38, 4)
    )                                                               AS total_cost_overwatch_usd,
    CAST(
        ROUND(SUM(ftr.total_cost_usd), 4) AS DECIMAL(38, 4)
    )                                                               AS total_cost_usd,

    BIGINT(
        UNIX_TIMESTAMP(MAX(ftr.ts_task_ended)) - UNIX_TIMESTAMP(MIN(ftr.ts_task_started))
    )                                                               AS total_wall_clock_seconds,
    BIGINT(SUM(ftr.execution_duration_seconds))                     AS total_execution_duration_seconds,
    BIGINT(SUM(ftr.setup_duration_seconds))                         AS total_setup_duration_seconds,
    MAX(ftr.init_script_seconds)                                    AS max_init_script_seconds,
    MAX(ftr.cluster_startup_seconds)                                AS max_cluster_startup_seconds,

    ROUND(
        SUM(ftr.p95_driver_cpu_busy_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE))), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_driver_cpu_busy_percent,
    ROUND(
        SUM(ftr.p95_worker_cpu_busy_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE))), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_worker_cpu_busy_percent,
    ROUND(
        SUM(ftr.p95_driver_mem_used_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE))), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_driver_mem_used_percent,
    ROUND(
        SUM(ftr.p95_worker_mem_used_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE))), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_worker_mem_used_percent,
    ROUND(
        SUM(ftr.local_disk_utilization_pct_p95 * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE))), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_local_disk_utilization_pct_p95,

    MAX(CASE WHEN ftr.is_failed THEN 1 ELSE 0 END) >= 1           AS is_any_task_failed,
    MAX(CASE WHEN ftr.is_success THEN 1 ELSE 0 END) >= 1          AS is_any_task_success,
    SUM(CASE WHEN ftr.is_pool_acquisition_slow THEN 1 ELSE 0 END) AS n_pool_acquisition_slow_tasks,

    SUM(ftr.total_executor_run_time_ms)                           AS total_executor_run_time_ms,
    SUM(ftr.total_disk_bytes_spilled)                             AS total_disk_bytes_spilled,
    SUM(ftr.total_memory_bytes_spilled)                           AS total_memory_bytes_spilled,
    SUM(ftr.total_input_bytes_read)                               AS total_input_bytes_read,
    MAX(ftr.max_peak_execution_memory_bytes)                      AS max_peak_execution_memory_bytes,
    MAX(ftr.max_jvm_heap_bytes)                                   AS max_jvm_heap_bytes,
    SUM(ftr.total_gc_time_ms)                                     AS total_gc_time_ms,
    MAX(ftr.max_task_skew_ratio)                                  AS max_task_skew_ratio,
    SUM(ftr.total_shuffle_bytes_read)                             AS total_shuffle_bytes_read,
    SUM(ftr.total_shuffle_bytes_written)                          AS total_shuffle_bytes_written,

    FIRST(ftr.pricing_sku    IGNORE NULLS)                        AS pricing_sku,
    FIRST(ftr.dbu_rate_usd   IGNORE NULLS)                        AS dbu_rate_usd,

    DATE(date_trunc('MINUTE', ftr.ts_run_started))                AS dt_dag_run_started,
    MIN(ftr.ts_run_started)                                       AS ts_run_started_min,
    MAX(ftr.ts_run_ended)                                         AS ts_run_ended_max,
    CURRENT_TIMESTAMP()                                           AS ts_load,
    YEAR(DATE(date_trunc('MINUTE', ftr.ts_run_started)))          AS year,
    MONTH(DATE(date_trunc('MINUTE', ftr.ts_run_started)))         AS month,
    DAY(DATE(date_trunc('MINUTE', ftr.ts_run_started)))           AS day
FROM
    dw_databricks_health.fact_databricks_task_run AS ftr
WHERE
    DATE(ftr.dt_task_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND ftr.airflow_dag_id IS NOT NULL
GROUP BY
    ftr.id_databricks_workspace,
    ftr.airflow_dag_id,
    date_trunc('MINUTE', ftr.ts_run_started)
