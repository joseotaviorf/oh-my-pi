-- ============================================================================
-- dag_health_wow.sql
--
-- Week-over-week comparison for Databricks DAG observability: each metric is
-- computed over the trailing 7 days ending on load_start_date ("current") and
-- the prior 7 days ("previous"), plus percent change. One row per
-- (airflow_dag_id, dt_window_end). Reads from dw_databricks_health.fact_databricks_dag_run UNION ALL
-- dw_emr_health.fact_emr_dag_run (filter via provisioner).
--
-- Window (14 calendar days):
--   previous_7d: load_start_date - 13 days through load_start_date - 7 days
--   current_7d:    load_start_date - 6 days through load_start_date
--
-- change_pct: ROUND((current - previous) / NULLIF(previous, 0) * 100, 2).
-- `total_cost_usd` sums logical-run totals (negotiated DBU USD + apportioned calculated EC2).
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
        cost_cohort,
        data_classification,
        primary_dbr_version,
        n_databricks_job_runs,
        n_task_runs,
        n_failed_task_runs,
        n_task_runs_with_stage_data,
        n_stage_attribution_ambiguous_task_runs,
        n_pool_acquisition_slow_tasks,
        is_any_task_failed,
        is_any_photon,
        is_any_pool_backed,
        is_any_local_nvme,
        total_dbu_consumed,
        total_dbu_cost_usd,
        total_ec2_cost_calculated_usd AS total_ec2_cost_usd,
        ec2_spot_hours,
        ec2_on_demand_hours,
        is_ec2_estimated,
        ec2_pricing_missing,
        total_cost_usd,
        total_wall_clock_seconds                           AS total_duration_seconds,
        total_execution_duration_seconds                   AS execution_duration_seconds,
        total_executor_run_time_ms,
        weighted_avg_p95_driver_cpu_busy_percent           AS p95_driver_cpu_busy_percent,
        weighted_avg_p95_worker_cpu_busy_percent           AS p95_worker_cpu_busy_percent,
        weighted_avg_p95_driver_mem_used_percent           AS p95_driver_mem_used_percent,
        weighted_avg_p95_worker_mem_used_percent           AS p95_worker_mem_used_percent,
        weighted_avg_p95_driver_cpu_wait_percent           AS p95_driver_cpu_wait_percent,
        weighted_avg_p95_worker_cpu_wait_percent           AS p95_worker_cpu_wait_percent,
        weighted_avg_p50_driver_cpu_busy_percent           AS p50_driver_cpu_busy_percent,
        weighted_avg_p50_worker_cpu_busy_percent           AS p50_worker_cpu_busy_percent,
        weighted_avg_p50_driver_cpu_wait_percent           AS p50_driver_cpu_wait_percent,
        weighted_avg_p50_worker_cpu_wait_percent           AS p50_worker_cpu_wait_percent,
        weighted_avg_p50_driver_mem_used_percent           AS p50_driver_mem_used_percent,
        weighted_avg_p50_worker_mem_used_percent           AS p50_worker_mem_used_percent,
        weighted_avg_local_disk_utilization_pct_p95        AS local_disk_utilization_pct_p95,
        stage_count,
        failed_stage_count,
        total_executor_cpu_time_ms,
        total_output_bytes_written,
        max_pre_init_script_seconds                        AS pre_init_script_seconds,
        max_post_init_script_seconds                       AS post_init_script_seconds,
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 6 DAYS           AS in_current_7d,
        dt_dag_run_started BETWEEN DATE('{load_start_date}') - INTERVAL 13 DAYS
            AND DATE('{load_start_date}') - INTERVAL 7 DAYS                      AS in_previous_7d
    FROM
        dw_databricks_health.fact_databricks_dag_run
    WHERE
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 13 DAYS
        AND dt_dag_run_started <= DATE('{load_start_date}')
        AND airflow_dag_id IS NOT NULL
    UNION ALL
SELECT
        airflow_dag_id,
        team_owner,
        cost_center,
        ecosystem,
        environment,
        provisioner,
        cost_cohort,
        data_classification,
        primary_dbr_version,
        n_databricks_job_runs,
        n_task_runs,
        n_failed_task_runs,
        n_task_runs_with_stage_data,
        n_stage_attribution_ambiguous_task_runs,
        n_pool_acquisition_slow_tasks,
        is_any_task_failed,
        is_any_photon,
        is_any_pool_backed,
        is_any_local_nvme,
        total_dbu_consumed,
        total_dbu_cost_usd,
        total_ec2_cost_usd,
        ec2_spot_hours,
        ec2_on_demand_hours,
        FALSE AS is_ec2_estimated,
        FALSE AS ec2_pricing_missing,
        total_cost_usd,
        total_wall_clock_seconds                           AS total_duration_seconds,
        total_execution_duration_seconds                   AS execution_duration_seconds,
        total_executor_run_time_ms,
        weighted_avg_p95_driver_cpu_busy_percent           AS p95_driver_cpu_busy_percent,
        weighted_avg_p95_worker_cpu_busy_percent           AS p95_worker_cpu_busy_percent,
        weighted_avg_p95_driver_mem_used_percent           AS p95_driver_mem_used_percent,
        weighted_avg_p95_worker_mem_used_percent           AS p95_worker_mem_used_percent,
        weighted_avg_p95_driver_cpu_wait_percent           AS p95_driver_cpu_wait_percent,
        weighted_avg_p95_worker_cpu_wait_percent           AS p95_worker_cpu_wait_percent,
        weighted_avg_p50_driver_cpu_busy_percent           AS p50_driver_cpu_busy_percent,
        weighted_avg_p50_worker_cpu_busy_percent           AS p50_worker_cpu_busy_percent,
        weighted_avg_p50_driver_cpu_wait_percent           AS p50_driver_cpu_wait_percent,
        weighted_avg_p50_worker_cpu_wait_percent           AS p50_worker_cpu_wait_percent,
        weighted_avg_p50_driver_mem_used_percent           AS p50_driver_mem_used_percent,
        weighted_avg_p50_worker_mem_used_percent           AS p50_worker_mem_used_percent,
        weighted_avg_local_disk_utilization_pct_p95        AS local_disk_utilization_pct_p95,
        stage_count,
        failed_stage_count,
        total_executor_cpu_time_ms,
        total_output_bytes_written,
        max_pre_init_script_seconds                        AS pre_init_script_seconds,
        max_post_init_script_seconds                       AS post_init_script_seconds,
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 6 DAYS           AS in_current_7d,
        dt_dag_run_started BETWEEN DATE('{load_start_date}') - INTERVAL 13 DAYS
            AND DATE('{load_start_date}') - INTERVAL 7 DAYS                      AS in_previous_7d
    FROM
        dw_emr_health.fact_emr_dag_run
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
            SUM(p50_driver_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p50_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p50_driver_cpu_busy_percent_current_7d,
        ROUND(
            SUM(p50_driver_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p50_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p50_driver_cpu_busy_percent_previous_7d,
        ROUND(
            SUM(p50_worker_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p50_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p50_worker_cpu_busy_percent_current_7d,
        ROUND(
            SUM(p50_worker_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p50_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p50_worker_cpu_busy_percent_previous_7d,
        ROUND(
            SUM(p50_driver_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p50_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p50_driver_cpu_wait_percent_current_7d,
        ROUND(
            SUM(p50_driver_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p50_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p50_driver_cpu_wait_percent_previous_7d,
        ROUND(
            SUM(p50_worker_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p50_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p50_worker_cpu_wait_percent_current_7d,
        ROUND(
            SUM(p50_worker_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p50_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p50_worker_cpu_wait_percent_previous_7d,
        ROUND(
            SUM(p50_driver_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p50_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p50_driver_mem_used_percent_current_7d,
        ROUND(
            SUM(p50_driver_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p50_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p50_driver_mem_used_percent_previous_7d,
        ROUND(
            SUM(p50_worker_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p50_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p50_worker_mem_used_percent_current_7d,
        ROUND(
            SUM(p50_worker_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p50_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p50_worker_mem_used_percent_previous_7d,
        ROUND(
            SUM(p95_driver_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p95_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p95_driver_cpu_wait_percent_current_7d,
        ROUND(
            SUM(p95_driver_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p95_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p95_driver_cpu_wait_percent_previous_7d,
        ROUND(
            SUM(p95_worker_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_current_7d)
                / NULLIF(SUM(CASE WHEN p95_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_current_7d), 0.0),
            2
        ) AS avg_p95_worker_cpu_wait_percent_current_7d,
        ROUND(
            SUM(p95_worker_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_previous_7d)
                / NULLIF(SUM(CASE WHEN p95_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_previous_7d), 0.0),
            2
        ) AS avg_p95_worker_cpu_wait_percent_previous_7d,
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
    -- --- Keys ---
    wr.airflow_dag_id                                                                          AS airflow_dag_id,
    -- --- Governance ---
    FIRST(team_owner)                                                                      AS team_owner,
    FIRST(cost_center)                                                                     AS cost_center,
    FIRST(ecosystem)                                                                       AS ecosystem,
    FIRST(environment)                                                                     AS environment,
    FIRST(provisioner)                                                                     AS provisioner,
    FIRST(cost_cohort)                                                                     AS cost_cohort,
    FIRST(data_classification)                                                           AS data_classification,
    -- --- Cluster profile ---
    FIRST(primary_dbr_version)                                                           AS primary_dbr_version,
    -- --- Cost ---
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
        SUM(total_ec2_cost_usd)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_ec2_cost_usd_current_7d,
    ROUND(
        SUM(total_ec2_cost_usd)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_ec2_cost_usd_previous_7d,
    ROUND(
        (
            SUM(total_ec2_cost_usd) FILTER (WHERE in_current_7d)
            - SUM(total_ec2_cost_usd) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(total_ec2_cost_usd) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_ec2_cost_usd_change_pct,
    ROUND(
        SUM(ec2_spot_hours)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS ec2_spot_hours_current_7d,
    ROUND(
        SUM(ec2_spot_hours)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS ec2_spot_hours_previous_7d,
    ROUND(
        (
            SUM(ec2_spot_hours) FILTER (WHERE in_current_7d)
            - SUM(ec2_spot_hours) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(ec2_spot_hours) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS ec2_spot_hours_change_pct,
    ROUND(
        SUM(ec2_on_demand_hours)
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS ec2_on_demand_hours_current_7d,
    ROUND(
        SUM(ec2_on_demand_hours)
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS ec2_on_demand_hours_previous_7d,
    ROUND(
        (
            SUM(ec2_on_demand_hours) FILTER (WHERE in_current_7d)
            - SUM(ec2_on_demand_hours) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(ec2_on_demand_hours) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS ec2_on_demand_hours_change_pct,
    BOOL_OR(is_ec2_estimated) FILTER (WHERE in_current_7d)                                 AS has_ec2_estimate_current_7d,
    BOOL_OR(is_ec2_estimated) FILTER (WHERE in_previous_7d)                                AS has_ec2_estimate_previous_7d,
    BOOL_OR(ec2_pricing_missing) FILTER (WHERE in_current_7d)                              AS has_ec2_pricing_missing_current_7d,
    BOOL_OR(ec2_pricing_missing) FILTER (WHERE in_previous_7d)                             AS has_ec2_pricing_missing_previous_7d,
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
        SUM(total_cost_usd) FILTER (WHERE in_current_7d)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_current_7d) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                      AS total_cost_usd_per_executor_second_current_7d,
    ROUND(
        SUM(total_cost_usd) FILTER (WHERE in_previous_7d)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                      AS total_cost_usd_per_executor_second_previous_7d,
    ROUND(
        (
            SUM(total_cost_usd) FILTER (WHERE in_current_7d)
                / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_current_7d) AS DOUBLE) / 1000.0, 0)
            - SUM(total_cost_usd) FILTER (WHERE in_previous_7d)
                / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0)
        ) * 100.0
            / NULLIF(
                SUM(total_cost_usd) FILTER (WHERE in_previous_7d)
                    / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0),
                0
            ),
        2
    )                                                                                      AS total_cost_usd_per_executor_second_change_pct,
    -- --- Volume ---
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
    -- --- Latency ---
    ROUND(AVG(total_duration_seconds) FILTER (WHERE in_current_7d),  2)                  AS avg_total_duration_seconds_current_7d,
    ROUND(AVG(total_duration_seconds) FILTER (WHERE in_previous_7d), 2)                  AS avg_total_duration_seconds_previous_7d,
    ROUND(
        (
            AVG(total_duration_seconds) FILTER (WHERE in_current_7d)
            - AVG(total_duration_seconds) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(AVG(total_duration_seconds) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS avg_total_duration_seconds_change_pct,
    -- --- Startup ---
    APPROX_PERCENTILE(pre_init_script_seconds, 0.95) FILTER (WHERE in_current_7d)        AS p95_pre_init_script_seconds_current_7d,
    APPROX_PERCENTILE(pre_init_script_seconds, 0.95) FILTER (WHERE in_previous_7d)       AS p95_pre_init_script_seconds_previous_7d,
    ROUND(
        (
            APPROX_PERCENTILE(pre_init_script_seconds, 0.95) FILTER (WHERE in_current_7d)
            - APPROX_PERCENTILE(pre_init_script_seconds, 0.95) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(APPROX_PERCENTILE(pre_init_script_seconds, 0.95) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS p95_pre_init_script_seconds_change_pct,
    APPROX_PERCENTILE(post_init_script_seconds, 0.95) FILTER (WHERE in_current_7d)         AS p95_post_init_script_seconds_current_7d,
    APPROX_PERCENTILE(post_init_script_seconds, 0.95) FILTER (WHERE in_previous_7d)        AS p95_post_init_script_seconds_previous_7d,
    ROUND(
        (
            APPROX_PERCENTILE(post_init_script_seconds, 0.95) FILTER (WHERE in_current_7d)
            - APPROX_PERCENTILE(post_init_script_seconds, 0.95) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(APPROX_PERCENTILE(post_init_script_seconds, 0.95) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS p95_post_init_script_seconds_change_pct,
    -- --- Reliability ---
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
    -- --- Utilisation ---
    MAX(wu.avg_p95_driver_cpu_busy_percent_current_7d)                                     AS avg_p95_driver_cpu_busy_percent_current_7d,
    MAX(wu.avg_p95_driver_cpu_busy_percent_previous_7d)                                    AS avg_p95_driver_cpu_busy_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_driver_cpu_busy_percent_current_7d)
            - MAX(wu.avg_p95_driver_cpu_busy_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_driver_cpu_busy_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_driver_cpu_busy_percent_change_pct,
    MAX(wu.avg_p95_worker_cpu_busy_percent_current_7d)                                     AS avg_p95_worker_cpu_busy_percent_current_7d,
    MAX(wu.avg_p95_worker_cpu_busy_percent_previous_7d)                                    AS avg_p95_worker_cpu_busy_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_worker_cpu_busy_percent_current_7d)
            - MAX(wu.avg_p95_worker_cpu_busy_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_worker_cpu_busy_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_worker_cpu_busy_percent_change_pct,
    MAX(wu.avg_p95_driver_mem_used_percent_current_7d)                                     AS avg_p95_driver_mem_used_percent_current_7d,
    MAX(wu.avg_p95_driver_mem_used_percent_previous_7d)                                    AS avg_p95_driver_mem_used_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_driver_mem_used_percent_current_7d)
            - MAX(wu.avg_p95_driver_mem_used_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_driver_mem_used_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_driver_mem_used_percent_change_pct,
    MAX(wu.avg_p95_worker_mem_used_percent_current_7d)                                     AS avg_p95_worker_mem_used_percent_current_7d,
    MAX(wu.avg_p95_worker_mem_used_percent_previous_7d)                                    AS avg_p95_worker_mem_used_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_worker_mem_used_percent_current_7d)
            - MAX(wu.avg_p95_worker_mem_used_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_worker_mem_used_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_worker_mem_used_percent_change_pct,
    MAX(wu.avg_p95_driver_cpu_wait_percent_current_7d)                                     AS avg_p95_driver_cpu_wait_percent_current_7d,
    MAX(wu.avg_p95_driver_cpu_wait_percent_previous_7d)                                    AS avg_p95_driver_cpu_wait_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_driver_cpu_wait_percent_current_7d)
            - MAX(wu.avg_p95_driver_cpu_wait_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_driver_cpu_wait_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_driver_cpu_wait_percent_change_pct,
    MAX(wu.avg_p95_worker_cpu_wait_percent_current_7d)                                     AS avg_p95_worker_cpu_wait_percent_current_7d,
    MAX(wu.avg_p95_worker_cpu_wait_percent_previous_7d)                                    AS avg_p95_worker_cpu_wait_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p95_worker_cpu_wait_percent_current_7d)
            - MAX(wu.avg_p95_worker_cpu_wait_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p95_worker_cpu_wait_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_worker_cpu_wait_percent_change_pct,
    MAX(wu.avg_p50_driver_cpu_busy_percent_current_7d)                                     AS avg_p50_driver_cpu_busy_percent_current_7d,
    MAX(wu.avg_p50_driver_cpu_busy_percent_previous_7d)                                    AS avg_p50_driver_cpu_busy_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p50_driver_cpu_busy_percent_current_7d)
            - MAX(wu.avg_p50_driver_cpu_busy_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p50_driver_cpu_busy_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p50_driver_cpu_busy_percent_change_pct,
    MAX(wu.avg_p50_worker_cpu_busy_percent_current_7d)                                     AS avg_p50_worker_cpu_busy_percent_current_7d,
    MAX(wu.avg_p50_worker_cpu_busy_percent_previous_7d)                                    AS avg_p50_worker_cpu_busy_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p50_worker_cpu_busy_percent_current_7d)
            - MAX(wu.avg_p50_worker_cpu_busy_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p50_worker_cpu_busy_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p50_worker_cpu_busy_percent_change_pct,
    MAX(wu.avg_p50_driver_cpu_wait_percent_current_7d)                                     AS avg_p50_driver_cpu_wait_percent_current_7d,
    MAX(wu.avg_p50_driver_cpu_wait_percent_previous_7d)                                    AS avg_p50_driver_cpu_wait_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p50_driver_cpu_wait_percent_current_7d)
            - MAX(wu.avg_p50_driver_cpu_wait_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p50_driver_cpu_wait_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p50_driver_cpu_wait_percent_change_pct,
    MAX(wu.avg_p50_worker_cpu_wait_percent_current_7d)                                     AS avg_p50_worker_cpu_wait_percent_current_7d,
    MAX(wu.avg_p50_worker_cpu_wait_percent_previous_7d)                                    AS avg_p50_worker_cpu_wait_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p50_worker_cpu_wait_percent_current_7d)
            - MAX(wu.avg_p50_worker_cpu_wait_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p50_worker_cpu_wait_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p50_worker_cpu_wait_percent_change_pct,
    MAX(wu.avg_p50_driver_mem_used_percent_current_7d)                                     AS avg_p50_driver_mem_used_percent_current_7d,
    MAX(wu.avg_p50_driver_mem_used_percent_previous_7d)                                    AS avg_p50_driver_mem_used_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p50_driver_mem_used_percent_current_7d)
            - MAX(wu.avg_p50_driver_mem_used_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p50_driver_mem_used_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p50_driver_mem_used_percent_change_pct,
    MAX(wu.avg_p50_worker_mem_used_percent_current_7d)                                     AS avg_p50_worker_mem_used_percent_current_7d,
    MAX(wu.avg_p50_worker_mem_used_percent_previous_7d)                                    AS avg_p50_worker_mem_used_percent_previous_7d,
    ROUND(
        (
            MAX(wu.avg_p50_worker_mem_used_percent_current_7d)
            - MAX(wu.avg_p50_worker_mem_used_percent_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_p50_worker_mem_used_percent_previous_7d), 0),
        2
    )                                                                                      AS avg_p50_worker_mem_used_percent_change_pct,
    MAX(wu.avg_local_disk_utilization_pct_p95_current_7d)                                  AS avg_local_disk_utilization_pct_p95_current_7d,
    MAX(wu.avg_local_disk_utilization_pct_p95_previous_7d)                                 AS avg_local_disk_utilization_pct_p95_previous_7d,
    ROUND(
        (
            MAX(wu.avg_local_disk_utilization_pct_p95_current_7d)
            - MAX(wu.avg_local_disk_utilization_pct_p95_previous_7d)
        ) * 100.0 / NULLIF(MAX(wu.avg_local_disk_utilization_pct_p95_previous_7d), 0),
        2
    )                                                                                      AS avg_local_disk_utilization_pct_p95_change_pct,
    -- --- Spark / memory / I/O ---
    SUM(total_executor_cpu_time_ms) FILTER (WHERE in_current_7d)                           AS total_executor_cpu_time_ms_current_7d,
    SUM(total_executor_cpu_time_ms) FILTER (WHERE in_previous_7d)                          AS total_executor_cpu_time_ms_previous_7d,
    ROUND(
        (
            SUM(total_executor_cpu_time_ms) FILTER (WHERE in_current_7d)
            - SUM(total_executor_cpu_time_ms) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(total_executor_cpu_time_ms) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_executor_cpu_time_ms_change_pct,
    SUM(total_output_bytes_written) FILTER (WHERE in_current_7d)                           AS total_output_bytes_written_current_7d,
    SUM(total_output_bytes_written) FILTER (WHERE in_previous_7d)                          AS total_output_bytes_written_previous_7d,
    ROUND(
        (
            SUM(total_output_bytes_written) FILTER (WHERE in_current_7d)
            - SUM(total_output_bytes_written) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(total_output_bytes_written) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_output_bytes_written_change_pct,
    SUM(stage_count) FILTER (WHERE in_current_7d)                                          AS total_stage_count_current_7d,
    SUM(stage_count) FILTER (WHERE in_previous_7d)                                         AS total_stage_count_previous_7d,
    ROUND(
        (
            SUM(stage_count) FILTER (WHERE in_current_7d)
            - SUM(stage_count) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(stage_count) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_stage_count_change_pct,
    SUM(failed_stage_count) FILTER (WHERE in_current_7d)                                   AS total_failed_stage_count_current_7d,
    SUM(failed_stage_count) FILTER (WHERE in_previous_7d)                                  AS total_failed_stage_count_previous_7d,
    ROUND(
        (
            SUM(failed_stage_count) FILTER (WHERE in_current_7d)
            - SUM(failed_stage_count) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(failed_stage_count) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_failed_stage_count_change_pct,
    ROUND(
        SUM(failed_stage_count) FILTER (WHERE in_current_7d) * 100.0
            / NULLIF(SUM(stage_count) FILTER (WHERE in_current_7d), 0),
        2
    )                                                                                      AS failed_stage_rate_pct_current_7d,
    ROUND(
        SUM(failed_stage_count) FILTER (WHERE in_previous_7d) * 100.0
            / NULLIF(SUM(stage_count) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS failed_stage_rate_pct_previous_7d,
    ROUND(
        (
            SUM(failed_stage_count) FILTER (WHERE in_current_7d) * 100.0
                / NULLIF(SUM(stage_count) FILTER (WHERE in_current_7d), 0)
            - SUM(failed_stage_count) FILTER (WHERE in_previous_7d) * 100.0
                / NULLIF(SUM(stage_count) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(failed_stage_count) FILTER (WHERE in_previous_7d) * 100.0
                    / NULLIF(SUM(stage_count) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS failed_stage_rate_pct_change_pct,
    ROUND(
        SUM(total_executor_cpu_time_ms) FILTER (WHERE in_current_7d)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_current_7d) AS DOUBLE), 0),
        4
    )                                                                                      AS executor_cpu_efficiency_ratio_current_7d,
    ROUND(
        SUM(total_executor_cpu_time_ms) FILTER (WHERE in_previous_7d)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE), 0),
        4
    )                                                                                      AS executor_cpu_efficiency_ratio_previous_7d,
    ROUND(
        (
            SUM(total_executor_cpu_time_ms) FILTER (WHERE in_current_7d)
                / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_current_7d) AS DOUBLE), 0)
            - SUM(total_executor_cpu_time_ms) FILTER (WHERE in_previous_7d)
                / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE), 0)
        ) * 100.0
            / NULLIF(
                SUM(total_executor_cpu_time_ms) FILTER (WHERE in_previous_7d)
                    / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE), 0),
                0
            ),
        2
    )                                                                                      AS executor_cpu_efficiency_ratio_change_pct,
    SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_current_7d)              AS stage_attribution_ambiguous_tasks_current_7d,
    SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_previous_7d)             AS stage_attribution_ambiguous_tasks_previous_7d,
    ROUND(
        (
            SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_current_7d)
            - SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS stage_attribution_ambiguous_tasks_change_pct,
    ROUND(
        SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_current_7d) * 100.0
            / NULLIF(SUM(n_task_runs) FILTER (WHERE in_current_7d), 0),
        2
    )                                                                                      AS stage_attribution_ambiguous_rate_pct_current_7d,
    ROUND(
        SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_previous_7d) * 100.0
            / NULLIF(SUM(n_task_runs) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS stage_attribution_ambiguous_rate_pct_previous_7d,
    ROUND(
        (
            SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_current_7d) * 100.0
                / NULLIF(SUM(n_task_runs) FILTER (WHERE in_current_7d), 0)
            - SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_previous_7d) * 100.0
                / NULLIF(SUM(n_task_runs) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_previous_7d) * 100.0
                    / NULLIF(SUM(n_task_runs) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS stage_attribution_ambiguous_rate_pct_change_pct,
    -- --- Cluster adoption ---
    ROUND(
        SUM(CASE WHEN is_any_photon THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0),
        2
    )                                                                                      AS photon_run_rate_pct_current_7d,
    ROUND(
        SUM(CASE WHEN is_any_photon THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS photon_run_rate_pct_previous_7d,
    ROUND(
        (
            SUM(CASE WHEN is_any_photon THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0)
            - SUM(CASE WHEN is_any_photon THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(CASE WHEN is_any_photon THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                    / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS photon_run_rate_pct_change_pct,
    ROUND(
        SUM(CASE WHEN is_any_pool_backed THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0),
        2
    )                                                                                      AS pool_backed_run_rate_pct_current_7d,
    ROUND(
        SUM(CASE WHEN is_any_pool_backed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS pool_backed_run_rate_pct_previous_7d,
    ROUND(
        (
            SUM(CASE WHEN is_any_pool_backed THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0)
            - SUM(CASE WHEN is_any_pool_backed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(CASE WHEN is_any_pool_backed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                    / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS pool_backed_run_rate_pct_change_pct,
    ROUND(
        SUM(CASE WHEN is_any_local_nvme THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0),
        2
    )                                                                                      AS local_nvme_run_rate_pct_current_7d,
    ROUND(
        SUM(CASE WHEN is_any_local_nvme THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS local_nvme_run_rate_pct_previous_7d,
    ROUND(
        (
            SUM(CASE WHEN is_any_local_nvme THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0)
            - SUM(CASE WHEN is_any_local_nvme THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0)
        ) * 100.0
            / NULLIF(
                SUM(CASE WHEN is_any_local_nvme THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                    / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
                0
            ),
        2
    )                                                                                      AS local_nvme_run_rate_pct_change_pct,
    -- --- Tail ---
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
