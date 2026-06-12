-- ============================================================================
-- enrich_rightsizing_outcomes.sql
--
-- Daily prod vs __validation twin comparison for cluster right-sizing feedback.
-- Grain: one row per (prod_airflow_dag_id, dt).
--
-- Join keys mirror the recalibration runbook / recommend_cluster_specs validation
-- SQL: REGEXP_REPLACE(airflow_dag_id, '__validation$', '') for validation twins.
--
-- Telemetry: per-task health percentiles rolled up to dag_run (p50/p95 CPU busy/
-- wait, memory), wall durations, peak_concurrent_workers, and failure flags.
-- Stage-derived task_run columns are intentionally excluded (~0% populated).
-- ============================================================================
WITH scoped_runs AS (
    SELECT
        CASE
            WHEN REGEXP_LIKE(airflow_dag_id, '__validation$')
                THEN REGEXP_REPLACE(airflow_dag_id, '__validation$', '')
            ELSE airflow_dag_id
        END                                                                          AS prod_airflow_dag_id,
        airflow_dag_id,
        REGEXP_LIKE(airflow_dag_id, '__validation$')                                 AS is_validation_side,
        dt_dag_run_started                                                             AS dt,
        total_cost_usd,
        total_wall_clock_seconds,
        weighted_avg_p50_driver_cpu_busy_percent                                     AS drv_cpu_p50,
        weighted_avg_p95_driver_cpu_busy_percent                                     AS drv_cpu_p95,
        weighted_avg_p95_driver_mem_used_percent                                     AS drv_mem_p95,
        weighted_avg_p50_worker_cpu_busy_percent                                     AS wrk_cpu_p50,
        weighted_avg_p95_worker_cpu_busy_percent                                     AS wrk_cpu_p95,
        weighted_avg_p95_worker_mem_used_percent                                     AS wrk_mem_p95,
        peak_concurrent_workers,
        is_any_task_failed,
        is_any_databricks_run_failed,
        driver_node_type,
        worker_node_type,
        worker_count,
        primary_dbr_version
    FROM dw_databricks_health.fact_databricks_dag_run
    WHERE dt_dag_run_started >= DATE('{load_start_date}')
      AND dt_dag_run_started <= DATE('{load_end_date}')
      AND airflow_dag_id LIKE 'bietlejuice.%'
      AND is_job_on_interactive = FALSE
      AND COALESCE(total_cost_usd, 0) > 0
),
dag_cadence AS (
    SELECT
        prod_airflow_dag_id,
        COUNT(DISTINCT dt)                                                           AS cadence_days,
        COUNT(*)                                                                     AS prod_runs_in_window,
        ROUND(1440.0 * COUNT(DISTINCT dt) / NULLIF(COUNT(*), 0), 1)                 AS schedule_interval_minutes
    FROM scoped_runs
    WHERE NOT is_validation_side
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
    GROUP BY prod_airflow_dag_id
),
daily_side AS (
    SELECT
        prod_airflow_dag_id,
        dt,
        is_validation_side,
        COUNT(*)                                                                     AS run_count,
        SUM(
            CASE
                WHEN is_any_task_failed OR is_any_databricks_run_failed THEN 1
                ELSE 0
            END
        )                                                                            AS failure_count,
        SUM(
            CASE
                WHEN NOT is_any_task_failed
                 AND NOT is_any_databricks_run_failed THEN 1
                ELSE 0
            END
        )                                                                            AS clean_run_count,
        ROUND(AVG(total_cost_usd), 6)                                                AS avg_cost_usd,
        ROUND(APPROX_PERCENTILE(total_wall_clock_seconds, 0.5) / 60.0, 1)           AS wall_p50_min,
        ROUND(APPROX_PERCENTILE(total_wall_clock_seconds, 0.95) / 60.0, 1)          AS wall_p95_min,
        ROUND(APPROX_PERCENTILE(drv_cpu_p50, 0.5), 1)                               AS drv_cpu_p50,
        ROUND(APPROX_PERCENTILE(drv_cpu_p95, 0.95), 1)                              AS drv_cpu_p95,
        ROUND(APPROX_PERCENTILE(drv_mem_p95, 0.95), 1)                              AS drv_mem_p95,
        ROUND(APPROX_PERCENTILE(wrk_cpu_p50, 0.5), 1)                               AS wrk_cpu_p50,
        ROUND(APPROX_PERCENTILE(wrk_cpu_p95, 0.95), 1)                              AS wrk_cpu_p95,
        ROUND(APPROX_PERCENTILE(wrk_mem_p95, 0.95), 1)                              AS wrk_mem_p95,
        MAX(peak_concurrent_workers)                                                   AS peak_concurrent_workers,
        any_value(driver_node_type IGNORE NULLS)                                       AS driver_node_type,
        any_value(worker_node_type IGNORE NULLS)                                       AS worker_node_type,
        any_value(worker_count IGNORE NULLS)                                           AS worker_count,
        any_value(primary_dbr_version IGNORE NULLS)                                    AS dbr_version
    FROM scoped_runs
    GROUP BY prod_airflow_dag_id, dt, is_validation_side
),
paired AS (
    SELECT
        prod.prod_airflow_dag_id,
        prod.dt,
        prod.run_count                                                               AS prod_run_count,
        COALESCE(val.run_count, 0)                                                     AS val_run_count,
        prod.failure_count                                                             AS prod_failure_count,
        COALESCE(val.failure_count, 0)                                                 AS val_failure_count,
        COALESCE(val.clean_run_count, 0)                                             AS val_clean_run_count,
        prod.avg_cost_usd                                                              AS prod_avg_cost_usd,
        val.avg_cost_usd                                                               AS val_avg_cost_usd,
        prod.wall_p50_min                                                            AS prod_wall_p50_min,
        prod.wall_p95_min                                                            AS prod_wall_p95_min,
        val.wall_p50_min                                                             AS val_wall_p50_min,
        val.wall_p95_min                                                             AS val_wall_p95_min,
        prod.drv_cpu_p50                                                             AS prod_drv_cpu_p50,
        prod.drv_cpu_p95                                                             AS prod_drv_cpu_p95,
        prod.drv_mem_p95                                                             AS prod_drv_mem_p95,
        prod.wrk_cpu_p50                                                             AS prod_wrk_cpu_p50,
        prod.wrk_cpu_p95                                                             AS prod_wrk_cpu_p95,
        prod.wrk_mem_p95                                                             AS prod_wrk_mem_p95,
        val.drv_cpu_p50                                                              AS val_drv_cpu_p50,
        val.drv_cpu_p95                                                              AS val_drv_cpu_p95,
        val.drv_mem_p95                                                              AS val_drv_mem_p95,
        val.wrk_cpu_p50                                                              AS val_wrk_cpu_p50,
        val.wrk_cpu_p95                                                              AS val_wrk_cpu_p95,
        val.wrk_mem_p95                                                              AS val_wrk_mem_p95,
        prod.peak_concurrent_workers                                                 AS prod_peak_concurrent_workers,
        val.peak_concurrent_workers                                                  AS val_peak_concurrent_workers,
        prod.driver_node_type                                                        AS prod_driver_node_type,
        prod.worker_node_type                                                        AS prod_worker_node_type,
        prod.worker_count                                                            AS prod_worker_count,
        prod.dbr_version                                                             AS prod_dbr_version,
        val.driver_node_type                                                         AS val_driver_node_type,
        val.worker_node_type                                                         AS val_worker_node_type,
        val.worker_count                                                             AS val_worker_count,
        val.dbr_version                                                              AS val_dbr_version
    FROM daily_side AS prod
    LEFT JOIN daily_side AS val
        ON prod.prod_airflow_dag_id = val.prod_airflow_dag_id
       AND prod.dt = val.dt
       AND val.is_validation_side = TRUE
    WHERE prod.is_validation_side = FALSE
),
scored AS (
    SELECT
        p.*,
        c.schedule_interval_minutes,
        CASE
            WHEN p.prod_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd > 0
             AND p.val_avg_cost_usd IS NOT NULL
                THEN ROUND(
                    (p.val_avg_cost_usd - p.prod_avg_cost_usd) / p.prod_avg_cost_usd * 100.0,
                    1
                )
        END                                                                          AS delta_cost_pct,
        CASE
            WHEN p.prod_wall_p50_min IS NOT NULL
             AND p.prod_wall_p50_min > 0
             AND p.val_wall_p50_min IS NOT NULL
                THEN ROUND(
                    (p.val_wall_p50_min - p.prod_wall_p50_min) / p.prod_wall_p50_min * 100.0,
                    1
                )
        END                                                                          AS delta_wall_p50_pct,
        CASE
            WHEN p.prod_wall_p95_min IS NOT NULL
             AND p.val_wall_p95_min IS NOT NULL
                THEN ROUND(p.val_wall_p95_min - p.prod_wall_p95_min, 1)
        END                                                                          AS delta_wall_p95_min,
        GREATEST(COALESCE(p.val_drv_mem_p95, 0), COALESCE(p.val_wrk_mem_p95, 0))    AS val_mem_p95_max,
        (
            p.val_clean_run_count >= 1
            AND p.val_failure_count = 0
            AND p.val_avg_cost_usd IS NOT NULL
            AND p.prod_avg_cost_usd IS NOT NULL
            AND p.val_avg_cost_usd < p.prod_avg_cost_usd
            AND (
                (
                    COALESCE(c.schedule_interval_minutes, 1440.0) > 120
                    AND p.val_wall_p50_min IS NOT NULL
                    AND p.prod_wall_p50_min IS NOT NULL
                    AND p.val_wall_p50_min <= 1.5 * p.prod_wall_p50_min
                )
                OR (
                    COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
                    AND p.val_wall_p95_min IS NOT NULL
                    AND p.prod_wall_p95_min IS NOT NULL
                    AND p.val_wall_p95_min <= GREATEST(
                        0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                        p.prod_wall_p95_min
                    )
                )
            )
        )                                                                            AS is_promote_eligible,
        CASE
            WHEN p.val_failure_count > 0 THEN 'fail'
            WHEN p.val_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd IS NOT NULL
             AND p.val_avg_cost_usd >= p.prod_avg_cost_usd THEN 'fail'
            WHEN p.val_clean_run_count < 1 THEN 'extend'
            WHEN COALESCE(c.schedule_interval_minutes, 1440.0) > 120
             AND p.val_wall_p50_min IS NOT NULL
             AND p.prod_wall_p50_min IS NOT NULL
             AND p.val_wall_p50_min > 1.5 * p.prod_wall_p50_min THEN 'fail'
            WHEN COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
             AND p.val_wall_p95_min IS NOT NULL
             AND p.prod_wall_p95_min IS NOT NULL
             AND p.val_wall_p95_min > GREATEST(
                0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                p.prod_wall_p95_min
             ) THEN 'fail'
            WHEN GREATEST(COALESCE(p.val_drv_mem_p95, 0), COALESCE(p.val_wrk_mem_p95, 0)) > 82
                THEN 'warn'
            WHEN p.val_clean_run_count >= 1
             AND p.val_failure_count = 0
             AND p.val_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd IS NOT NULL
             AND p.val_avg_cost_usd < p.prod_avg_cost_usd
             AND (
                (
                    COALESCE(c.schedule_interval_minutes, 1440.0) > 120
                    AND p.val_wall_p50_min IS NOT NULL
                    AND p.prod_wall_p50_min IS NOT NULL
                    AND p.val_wall_p50_min <= 1.5 * p.prod_wall_p50_min
                )
                OR (
                    COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
                    AND p.val_wall_p95_min IS NOT NULL
                    AND p.prod_wall_p95_min IS NOT NULL
                    AND p.val_wall_p95_min <= GREATEST(
                        0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                        p.prod_wall_p95_min
                    )
                )
             ) THEN 'pass'
            ELSE 'extend'
        END                                                                          AS outcome,
        CASE
            WHEN p.val_failure_count > 0 THEN 'reject'
            WHEN p.val_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd IS NOT NULL
             AND p.val_avg_cost_usd >= p.prod_avg_cost_usd THEN 'reject'
            WHEN COALESCE(c.schedule_interval_minutes, 1440.0) > 120
             AND p.val_wall_p50_min IS NOT NULL
             AND p.prod_wall_p50_min IS NOT NULL
             AND p.val_wall_p50_min > 1.5 * p.prod_wall_p50_min THEN 'reject'
            WHEN COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
             AND p.val_wall_p95_min IS NOT NULL
             AND p.prod_wall_p95_min IS NOT NULL
             AND p.val_wall_p95_min > GREATEST(
                0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                p.prod_wall_p95_min
             ) THEN 'reject'
            WHEN p.val_clean_run_count < 1 THEN 'extend'
            WHEN GREATEST(COALESCE(p.val_drv_mem_p95, 0), COALESCE(p.val_wrk_mem_p95, 0)) > 82
                THEN 'extend'
            WHEN p.val_clean_run_count >= 1
             AND p.val_failure_count = 0
             AND p.val_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd IS NOT NULL
             AND p.val_avg_cost_usd < p.prod_avg_cost_usd
             AND (
                (
                    COALESCE(c.schedule_interval_minutes, 1440.0) > 120
                    AND p.val_wall_p50_min IS NOT NULL
                    AND p.prod_wall_p50_min IS NOT NULL
                    AND p.val_wall_p50_min <= 1.5 * p.prod_wall_p50_min
                )
                OR (
                    COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
                    AND p.val_wall_p95_min IS NOT NULL
                    AND p.prod_wall_p95_min IS NOT NULL
                    AND p.val_wall_p95_min <= GREATEST(
                        0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                        p.prod_wall_p95_min
                    )
                )
             ) THEN 'promote'
            ELSE 'extend'
        END                                                                          AS promotion_action
    FROM paired AS p
    LEFT JOIN dag_cadence AS c
        ON p.prod_airflow_dag_id = c.prod_airflow_dag_id
)
SELECT
    prod_airflow_dag_id,
    dt,
    schedule_interval_minutes,
    prod_run_count,
    val_run_count,
    prod_failure_count,
    val_failure_count,
    val_clean_run_count,
    prod_avg_cost_usd,
    val_avg_cost_usd,
    prod_wall_p50_min,
    prod_wall_p95_min,
    val_wall_p50_min,
    val_wall_p95_min,
    prod_drv_cpu_p50,
    prod_drv_cpu_p95,
    prod_drv_mem_p95,
    prod_wrk_cpu_p50,
    prod_wrk_cpu_p95,
    prod_wrk_mem_p95,
    val_drv_cpu_p50,
    val_drv_cpu_p95,
    val_drv_mem_p95,
    val_wrk_cpu_p50,
    val_wrk_cpu_p95,
    val_wrk_mem_p95,
    prod_peak_concurrent_workers,
    val_peak_concurrent_workers,
    prod_driver_node_type,
    prod_worker_node_type,
    prod_worker_count,
    prod_dbr_version,
    val_driver_node_type,
    val_worker_node_type,
    val_worker_count,
    val_dbr_version,
    delta_cost_pct,
    delta_wall_p50_pct,
    delta_wall_p95_min,
    val_mem_p95_max,
    is_promote_eligible,
    outcome,
    promotion_action,
    CURRENT_TIMESTAMP()                                                            AS ts_load
FROM scored
