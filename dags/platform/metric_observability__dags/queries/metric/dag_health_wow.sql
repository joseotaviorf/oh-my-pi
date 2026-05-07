-- ============================================================================
-- dag_health_wow.sql
--
-- Week-over-week comparison for Databricks DAG observability: each metric is
-- computed over the trailing 7 days ending on load_start_date ("current") and
-- the prior 7 days ("previous"), plus percent change. One row per
-- (airflow_dag_id, dt_window_end). Reads exclusively from
-- dw_databricks_health.fact_databricks_dag_run.
--
-- Window (14 calendar days):
--   previous_7d: load_start_date - 13 days through load_start_date - 7 days
--   current_7d:    load_start_date - 6 days through load_start_date
--
-- change_pct: ROUND((current - previous) / NULLIF(previous, 0) * 100, 2).
-- `total_cost_usd` sums logical-run totals (DBU USD list + apportioned calculated EC2).
--
-- P95 utilisation metrics: weighted by execution_duration_seconds so that heavier runs
-- contribute proportionally. Runs with NULL utilisation are excluded from both
-- numerator and denominator.
-- ============================================================================
WITH window_runs AS (
    SELECT
        airflow_dag_id,
        team_owner,
        cost_center,
        ecosystem,
        environment,
        provisioner,
        n_databricks_job_runs,
        n_task_runs,
        n_failed_task_runs,
        n_task_runs_with_stage_data,
        n_pool_acquisition_slow_tasks,
        is_any_task_failed,
        total_dbu_consumed,
        total_dbu_cost_usd,
        total_ec2_cost_calculated_usd,
        spot_hours,
        on_demand_hours,
        total_cost_usd,
        total_ec2_cost_overwatch_usd,
        total_dbu_cost_overwatch_usd,
        total_cost_overwatch_usd,
        total_wall_clock_seconds                           AS total_duration_seconds,
        total_execution_duration_seconds                   AS execution_duration_seconds,
        total_executor_run_time_ms,
        weighted_avg_p95_driver_cpu_busy_percent           AS p95_driver_cpu_busy_percent,
        weighted_avg_p95_worker_cpu_busy_percent           AS p95_worker_cpu_busy_percent,
        weighted_avg_p95_driver_mem_used_percent           AS p95_driver_mem_used_percent,
        weighted_avg_p95_worker_mem_used_percent           AS p95_worker_mem_used_percent,
        weighted_avg_local_disk_utilization_pct_p95        AS local_disk_utilization_pct_p95,
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 6 DAYS           AS in_current_7d,
        dt_dag_run_started BETWEEN DATE('{load_start_date}') - INTERVAL 13 DAYS
            AND DATE('{load_start_date}') - INTERVAL 7 DAYS                      AS in_previous_7d
    FROM
        dw_databricks_health.fact_databricks_dag_run
    WHERE
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 13 DAYS
        AND dt_dag_run_started <= DATE('{load_start_date}')
        AND airflow_dag_id IS NOT NULL
),
-- Duration-weighted P95 cluster utilisation per DAG for current and previous windows.
-- Runs with NULL p95 are excluded from both numerator and denominator.
weighted_util AS (
    SELECT
        airflow_dag_id,
        ROUND(
            SUM(p95_driver_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p95_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p95_driver_cpu_busy_percent_current_7d,
        ROUND(
            SUM(p95_driver_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p95_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p95_driver_cpu_busy_percent_previous_7d,
        ROUND(
            SUM(p95_worker_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p95_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p95_worker_cpu_busy_percent_current_7d,
        ROUND(
            SUM(p95_worker_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p95_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p95_worker_cpu_busy_percent_previous_7d,
        ROUND(
            SUM(p95_driver_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p95_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p95_driver_mem_used_percent_current_7d,
        ROUND(
            SUM(p95_driver_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p95_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p95_driver_mem_used_percent_previous_7d,
        ROUND(
            SUM(p95_worker_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p95_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p95_worker_mem_used_percent_current_7d,
        ROUND(
            SUM(p95_worker_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p95_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p95_worker_mem_used_percent_previous_7d,
        ROUND(
            SUM(local_disk_utilization_pct_p95 * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN local_disk_utilization_pct_p95 IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_local_disk_utilization_pct_p95_current_7d,
        ROUND(
            SUM(local_disk_utilization_pct_p95 * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN local_disk_utilization_pct_p95 IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_local_disk_utilization_pct_p95_previous_7d
    FROM window_runs
    GROUP BY airflow_dag_id
)
SELECT
    wr.airflow_dag_id                                                                          AS airflow_dag_id,
    FIRST(team_owner)                                                                      AS team_owner,
    FIRST(cost_center)                                                                     AS cost_center,
    FIRST(ecosystem)                                                                       AS ecosystem,
    FIRST(environment)                                                                     AS environment,
    FIRST(provisioner)                                                                     AS provisioner,

    COUNT(*) FILTER (WHERE in_current_7d)                                                AS total_dag_runs_current_7d,
    COUNT(*) FILTER (WHERE in_previous_7d)                                                AS total_dag_runs_previous_7d,
    ROUND(
        (
            CAST(COUNT(*) FILTER (WHERE in_current_7d) AS DOUBLE)
            - CAST(COUNT(*) FILTER (WHERE in_previous_7d) AS DOUBLE)
        ) * 100.0
            / NULLIF(CAST(COUNT(*) FILTER (WHERE in_previous_7d) AS DOUBLE), 0),
        2
    )                                                                                      AS total_dag_runs_change_pct,

    SUM(n_databricks_job_runs) FILTER (WHERE in_current_7d)                             AS total_job_runs_current_7d,
    SUM(n_databricks_job_runs) FILTER (WHERE in_previous_7d)                             AS total_job_runs_previous_7d,
    ROUND(
        (
            CAST(SUM(n_databricks_job_runs) FILTER (WHERE in_current_7d) AS DOUBLE)
            - CAST(SUM(n_databricks_job_runs) FILTER (WHERE in_previous_7d) AS DOUBLE)
        ) * 100.0
            / NULLIF(CAST(SUM(n_databricks_job_runs) FILTER (WHERE in_previous_7d) AS DOUBLE), 0),
        2
    )                                                                                      AS total_job_runs_change_pct,

    SUM(n_task_runs) FILTER (WHERE in_current_7d)                                       AS total_task_runs_current_7d,
    SUM(n_task_runs) FILTER (WHERE in_previous_7d)                                       AS total_task_runs_previous_7d,
    ROUND(
        (
            CAST(SUM(n_task_runs) FILTER (WHERE in_current_7d) AS DOUBLE)
            - CAST(SUM(n_task_runs) FILTER (WHERE in_previous_7d) AS DOUBLE)
        ) * 100.0
            / NULLIF(CAST(SUM(n_task_runs) FILTER (WHERE in_previous_7d) AS DOUBLE), 0),
        2
    )                                                                                      AS total_task_runs_change_pct,

    ROUND(SUM(total_dbu_consumed) FILTER (WHERE in_current_7d),  4)                             AS total_dbu_consumed_current_7d,
    ROUND(SUM(total_dbu_consumed) FILTER (WHERE in_previous_7d), 4)                             AS total_dbu_consumed_previous_7d,
    ROUND(
        (
            SUM(total_dbu_consumed) FILTER (WHERE in_current_7d)
            - SUM(total_dbu_consumed) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(total_dbu_consumed) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_dbu_consumed_change_pct,

    ROUND(SUM(total_dbu_cost_usd) FILTER (WHERE in_current_7d),  4)                      AS total_dbu_cost_usd_current_7d,
    ROUND(SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d), 4)                      AS total_dbu_cost_usd_previous_7d,
    ROUND(
        (
            SUM(total_dbu_cost_usd) FILTER (WHERE in_current_7d)
            - SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_dbu_cost_usd_change_pct,

    ROUND(
        SUM(total_ec2_cost_calculated_usd)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_ec2_cost_calculated_usd_current_7d,
    ROUND(
        SUM(total_ec2_cost_calculated_usd)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_ec2_cost_calculated_usd_previous_7d,
    ROUND(
        (
            SUM(total_ec2_cost_calculated_usd) FILTER (WHERE in_current_7d)
            - SUM(total_ec2_cost_calculated_usd) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(total_ec2_cost_calculated_usd) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_ec2_cost_calculated_usd_change_pct,

    ROUND(
        SUM(spot_hours)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS spot_hours_current_7d,
    ROUND(
        SUM(spot_hours)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS spot_hours_previous_7d,
    ROUND(
        (
            SUM(spot_hours) FILTER (WHERE in_current_7d)
            - SUM(spot_hours) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(spot_hours) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS spot_hours_change_pct,

    ROUND(
        SUM(on_demand_hours)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS on_demand_hours_current_7d,
    ROUND(
        SUM(on_demand_hours)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS on_demand_hours_previous_7d,
    ROUND(
        (
            SUM(on_demand_hours) FILTER (WHERE in_current_7d)
            - SUM(on_demand_hours) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(on_demand_hours) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS on_demand_hours_change_pct,

    ROUND(SUM(total_cost_usd) FILTER (WHERE in_current_7d), 4)                             AS total_cost_usd_current_7d,
    ROUND(SUM(total_cost_usd) FILTER (WHERE in_previous_7d), 4)                             AS total_cost_usd_previous_7d,
    ROUND(
        (
            SUM(total_cost_usd) FILTER (WHERE in_current_7d)
            - SUM(total_cost_usd) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(total_cost_usd) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_cost_usd_change_pct,

    ROUND(
        SUM(total_dbu_cost_usd) FILTER (WHERE in_current_7d)
            / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0),
        4
    )                                                                                      AS avg_dbu_cost_usd_per_dag_run_current_7d,
    ROUND(
        SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d)
            / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
        4
    )                                                                                      AS avg_dbu_cost_usd_per_dag_run_previous_7d,
    ROUND(
        (
            SUM(total_dbu_cost_usd) FILTER (WHERE in_current_7d)
                / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0)
            - SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d)
                / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d)
                    / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS avg_dbu_cost_usd_per_dag_run_change_pct,

    ROUND(
        SUM(total_cost_usd) FILTER (WHERE in_current_7d)
            / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0),
        4
    )                                                                                      AS avg_total_cost_usd_per_dag_run_current_7d,
    ROUND(
        SUM(total_cost_usd) FILTER (WHERE in_previous_7d)
            / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
        4
    )                                                                                      AS avg_total_cost_usd_per_dag_run_previous_7d,
    ROUND(
        (
            SUM(total_cost_usd) FILTER (WHERE in_current_7d)
                / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0)
            - SUM(total_cost_usd) FILTER (WHERE in_previous_7d)
                / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(total_cost_usd) FILTER (WHERE in_previous_7d)
                    / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS avg_total_cost_usd_per_dag_run_change_pct,

    ROUND(
        SUM(total_dbu_cost_usd) FILTER (WHERE in_current_7d)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_current_7d) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                      AS cost_efficiency_usd_per_executor_second_current_7d,
    ROUND(
        SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                      AS cost_efficiency_usd_per_executor_second_previous_7d,
    ROUND(
        (
            SUM(total_dbu_cost_usd) FILTER (WHERE in_current_7d)
                / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_current_7d) AS DOUBLE) / 1000.0, 0)
            - SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d)
                / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0)
        ) * 100.0
            / NULLIF(
                SUM(total_dbu_cost_usd) FILTER (WHERE in_previous_7d)
                    / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0),
                0
            ),
        2
    )                                                                                      AS cost_efficiency_usd_per_executor_second_change_pct,

    ROUND(
        SUM(total_ec2_cost_overwatch_usd)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_ec2_cost_overwatch_usd_current_7d,
    ROUND(
        SUM(total_ec2_cost_overwatch_usd)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_ec2_cost_overwatch_usd_previous_7d,
    ROUND(
        (
            SUM(total_ec2_cost_overwatch_usd) FILTER (WHERE in_current_7d)
            - SUM(total_ec2_cost_overwatch_usd) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(total_ec2_cost_overwatch_usd) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_ec2_cost_overwatch_usd_change_pct,

    ROUND(
        SUM(total_dbu_cost_overwatch_usd)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_dbu_cost_overwatch_usd_current_7d,
    ROUND(
        SUM(total_dbu_cost_overwatch_usd)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_dbu_cost_overwatch_usd_previous_7d,
    ROUND(
        (
            SUM(total_dbu_cost_overwatch_usd) FILTER (WHERE in_current_7d)
            - SUM(total_dbu_cost_overwatch_usd) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(total_dbu_cost_overwatch_usd) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_dbu_cost_overwatch_usd_change_pct,

    ROUND(
        SUM(total_cost_overwatch_usd)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_cost_overwatch_usd_current_7d,
    ROUND(
        SUM(total_cost_overwatch_usd)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_cost_overwatch_usd_previous_7d,
    ROUND(
        (
            SUM(total_cost_overwatch_usd) FILTER (WHERE in_current_7d)
            - SUM(total_cost_overwatch_usd) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(total_cost_overwatch_usd) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_cost_overwatch_usd_change_pct,

    MAX(wu.avg_p95_worker_cpu_busy_percent_current_7d)                                     AS avg_p95_worker_cpu_busy_percent_current_7d,
    MAX(wu.avg_p95_worker_cpu_busy_percent_previous_7d)                                    AS avg_p95_worker_cpu_busy_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_worker_cpu_busy_percent_current_7d)
            - MAX(wu.avg_p95_worker_cpu_busy_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_worker_cpu_busy_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_worker_cpu_busy_percent_change_pct,

    MAX(wu.avg_p95_driver_cpu_busy_percent_current_7d)                                     AS avg_p95_driver_cpu_busy_percent_current_7d,
    MAX(wu.avg_p95_driver_cpu_busy_percent_previous_7d)                                    AS avg_p95_driver_cpu_busy_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_driver_cpu_busy_percent_current_7d)
            - MAX(wu.avg_p95_driver_cpu_busy_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_driver_cpu_busy_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_driver_cpu_busy_percent_change_pct,

    MAX(wu.avg_p95_worker_mem_used_percent_current_7d)                                     AS avg_p95_worker_mem_used_percent_current_7d,
    MAX(wu.avg_p95_worker_mem_used_percent_previous_7d)                                    AS avg_p95_worker_mem_used_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_worker_mem_used_percent_current_7d)
            - MAX(wu.avg_p95_worker_mem_used_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_worker_mem_used_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_worker_mem_used_percent_change_pct,

    MAX(wu.avg_p95_driver_mem_used_percent_current_7d)                                     AS avg_p95_driver_mem_used_percent_current_7d,
    MAX(wu.avg_p95_driver_mem_used_percent_previous_7d)                                    AS avg_p95_driver_mem_used_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_driver_mem_used_percent_current_7d)
            - MAX(wu.avg_p95_driver_mem_used_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_driver_mem_used_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_driver_mem_used_percent_change_pct,

    MAX(wu.avg_local_disk_utilization_pct_p95_current_7d)                                  AS avg_local_disk_utilization_pct_p95_current_7d,
    MAX(wu.avg_local_disk_utilization_pct_p95_previous_7d)                                 AS avg_local_disk_utilization_pct_p95_previous_7d,
    ROUND(
        (
            MAX(wu.avg_local_disk_utilization_pct_p95_current_7d)
            - MAX(wu.avg_local_disk_utilization_pct_p95_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_local_disk_utilization_pct_p95_previous_7d), 0),
        2
    )                                                                                      AS avg_local_disk_utilization_pct_p95_change_pct,

    ROUND(AVG(total_duration_seconds) FILTER (WHERE in_current_7d),  2)                  AS avg_total_duration_seconds_current_7d,
    ROUND(AVG(total_duration_seconds) FILTER (WHERE in_previous_7d), 2)                  AS avg_total_duration_seconds_previous_7d,
    ROUND(
        (
            AVG(total_duration_seconds) FILTER (WHERE in_current_7d)
            - AVG(total_duration_seconds) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(AVG(total_duration_seconds) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS avg_total_duration_seconds_change_pct,

    ROUND(
        SUM(n_failed_task_runs) FILTER (WHERE in_current_7d) * 100.0
            / NULLIF(SUM(n_task_runs) FILTER (WHERE in_current_7d), 0),
        2
    )                                                                                      AS error_rate_pct_current_7d,
    ROUND(
        SUM(n_failed_task_runs) FILTER (WHERE in_previous_7d) * 100.0
            / NULLIF(SUM(n_task_runs) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS error_rate_pct_previous_7d,
    ROUND(
        (
            SUM(n_failed_task_runs) FILTER (WHERE in_current_7d) * 100.0
                / NULLIF(SUM(n_task_runs) FILTER (WHERE in_current_7d), 0)
            - SUM(n_failed_task_runs) FILTER (WHERE in_previous_7d) * 100.0
                / NULLIF(SUM(n_task_runs) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(n_failed_task_runs) FILTER (WHERE in_previous_7d) * 100.0
                    / NULLIF(SUM(n_task_runs) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS error_rate_pct_change_pct,

    ROUND(
        SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0),
        2
    )                                                                                      AS failed_dag_run_rate_pct_current_7d,
    ROUND(
        SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS failed_dag_run_rate_pct_previous_7d,
    ROUND(
        (
            SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0)
            - SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                    / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS failed_dag_run_rate_pct_change_pct,

    DATE('{load_start_date}')                                                              AS dt_window_end,
    CURRENT_TIMESTAMP()                                                                    AS ts_load,
    YEAR(DATE('{load_start_date}'))                                                        AS year,
    MONTH(DATE('{load_start_date}'))                                                       AS month,
    DAY(DATE('{load_start_date}'))                                                         AS day

FROM
    window_runs wr
    LEFT JOIN weighted_util wu ON wr.airflow_dag_id = wu.airflow_dag_id
GROUP BY
    wr.airflow_dag_id
