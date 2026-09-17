-- ============================================================================
-- dag_health.sql
--
-- Per-DAG rolling observability metrics computed daily over TWO trailing
-- windows simultaneously: 7 days and 28 days. One row per
-- (airflow_dag_id, dt_window_end). Reads from dw_databricks_health.fact_databricks_dag_run UNION ALL
-- dw_emr_health.fact_emr_dag_run (logical Airflow run grain; provisioner discriminates).
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
--   total_dag_runs_*  — COUNT(*) logical runs (same minute bucket via
--       fact_databricks_dag_run).
--   total_job_runs_*  — SUM(n_databricks_job_runs).
--   total_task_runs_* — SUM(n_task_runs).
--
-- Cost: SUM task-grain apportioned columns from the DAG-run fact (no cluster-day
-- dedupe). total_cost_usd is negotiated DBU USD + apportioned calculated EC2 USD per task,
-- summed to logical-run grain.
--
-- P95 utilisation metrics (avg_p95_*): weighted by execution_duration_seconds so that
-- heavier runs dominate proportionally. Runs with NULL utilisation (no cluster data)
-- are excluded from both numerator and denominator.
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
        is_any_stage_attribution_ambiguous,
        dt_dag_run_started,
        ts_logical_run_started,
        total_wall_clock_seconds                          AS total_duration_seconds,
        total_execution_duration_seconds                  AS execution_duration_seconds,
        total_setup_duration_seconds                      AS setup_duration_seconds,
        max_pre_init_script_seconds                       AS pre_init_script_seconds,
        max_init_script_seconds                           AS init_script_seconds,
        max_post_init_script_seconds                      AS post_init_script_seconds,
        max_cluster_startup_seconds                       AS cluster_startup_seconds,
        total_dbu_consumed,
        total_dbu_cost_usd,
        total_ec2_cost_calculated_usd AS total_ec2_cost_usd,
        CAST(NULL AS DECIMAL(38, 4))                      AS total_ec2_net_cost_usd,
        CAST(NULL AS DECIMAL(38, 4))                      AS total_net_cost_usd,
        CAST(NULL AS DECIMAL(38, 4))                      AS total_discount_usd,
        ec2_spot_hours,
        ec2_on_demand_hours,
        is_ec2_estimated,
        ec2_pricing_missing,
        total_cost_usd,
        weighted_avg_p95_driver_cpu_busy_percent          AS p95_driver_cpu_busy_percent,
        weighted_avg_p95_worker_cpu_busy_percent          AS p95_worker_cpu_busy_percent,
        weighted_avg_p95_driver_mem_used_percent          AS p95_driver_mem_used_percent,
        weighted_avg_p95_worker_mem_used_percent          AS p95_worker_mem_used_percent,
        weighted_avg_p95_driver_cpu_wait_percent          AS p95_driver_cpu_wait_percent,
        weighted_avg_p95_worker_cpu_wait_percent          AS p95_worker_cpu_wait_percent,
        weighted_avg_p50_driver_cpu_busy_percent          AS p50_driver_cpu_busy_percent,
        weighted_avg_p50_worker_cpu_busy_percent          AS p50_worker_cpu_busy_percent,
        weighted_avg_p50_driver_cpu_wait_percent          AS p50_driver_cpu_wait_percent,
        weighted_avg_p50_worker_cpu_wait_percent          AS p50_worker_cpu_wait_percent,
        weighted_avg_p50_driver_mem_used_percent          AS p50_driver_mem_used_percent,
        weighted_avg_p50_worker_mem_used_percent          AS p50_worker_mem_used_percent,
        weighted_avg_local_disk_utilization_pct_p95       AS local_disk_utilization_pct_p95,
        stage_count,
        failed_stage_count,
        total_executor_run_time_ms,
        total_executor_cpu_time_ms,
        total_disk_bytes_spilled,
        total_memory_bytes_spilled,
        total_input_bytes_read,
        total_output_bytes_written,
        max_peak_execution_memory_bytes,
        max_jvm_heap_bytes,
        total_gc_time_ms,
        max_task_skew_ratio,
        total_shuffle_bytes_read,
        total_shuffle_bytes_written,
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 6 DAYS AS in_7d_window
    FROM
        dw_databricks_health.fact_databricks_dag_run
    WHERE
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 27 DAYS
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
        is_any_stage_attribution_ambiguous,
        dt_dag_run_started,
        ts_logical_run_started,
        total_wall_clock_seconds                          AS total_duration_seconds,
        total_execution_duration_seconds                  AS execution_duration_seconds,
        total_setup_duration_seconds                      AS setup_duration_seconds,
        max_pre_init_script_seconds                       AS pre_init_script_seconds,
        max_init_script_seconds                           AS init_script_seconds,
        max_post_init_script_seconds                      AS post_init_script_seconds,
        max_cluster_startup_seconds                       AS cluster_startup_seconds,
        total_dbu_consumed,
        total_dbu_cost_usd,
        total_ec2_cost_usd,
        total_ec2_net_cost_usd,
        total_net_cost_usd,
        total_discount_usd,
        ec2_spot_hours,
        ec2_on_demand_hours,
        FALSE AS is_ec2_estimated,
        FALSE AS ec2_pricing_missing,
        total_cost_usd,
        weighted_avg_p95_driver_cpu_busy_percent          AS p95_driver_cpu_busy_percent,
        weighted_avg_p95_worker_cpu_busy_percent          AS p95_worker_cpu_busy_percent,
        weighted_avg_p95_driver_mem_used_percent          AS p95_driver_mem_used_percent,
        weighted_avg_p95_worker_mem_used_percent          AS p95_worker_mem_used_percent,
        weighted_avg_p95_driver_cpu_wait_percent          AS p95_driver_cpu_wait_percent,
        weighted_avg_p95_worker_cpu_wait_percent          AS p95_worker_cpu_wait_percent,
        weighted_avg_p50_driver_cpu_busy_percent          AS p50_driver_cpu_busy_percent,
        weighted_avg_p50_worker_cpu_busy_percent          AS p50_worker_cpu_busy_percent,
        weighted_avg_p50_driver_cpu_wait_percent          AS p50_driver_cpu_wait_percent,
        weighted_avg_p50_worker_cpu_wait_percent          AS p50_worker_cpu_wait_percent,
        weighted_avg_p50_driver_mem_used_percent          AS p50_driver_mem_used_percent,
        weighted_avg_p50_worker_mem_used_percent          AS p50_worker_mem_used_percent,
        weighted_avg_local_disk_utilization_pct_p95       AS local_disk_utilization_pct_p95,
        stage_count,
        failed_stage_count,
        total_executor_run_time_ms,
        total_executor_cpu_time_ms,
        total_disk_bytes_spilled,
        total_memory_bytes_spilled,
        total_input_bytes_read,
        total_output_bytes_written,
        max_peak_execution_memory_bytes,
        max_jvm_heap_bytes,
        total_gc_time_ms,
        max_task_skew_ratio,
        total_shuffle_bytes_read,
        total_shuffle_bytes_written,
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 6 DAYS AS in_7d_window
    FROM
        dw_emr_health.fact_emr_dag_run
    WHERE
        dt_dag_run_started >= DATE('{load_start_date}') - INTERVAL 27 DAYS
        AND dt_dag_run_started <= DATE('{load_start_date}')
        AND airflow_dag_id IS NOT NULL
),
-- Duration-weighted P95 cluster utilisation per DAG for both windows.
-- Uses execution_duration_seconds as weight; runs with NULL p95 are excluded
-- from both numerator and denominator so they don't dilute the average.
weighted_util AS (
    SELECT
        airflow_dag_id,
        ROUND(
            SUM(p95_driver_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p95_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p95_driver_cpu_busy_percent_7d,
        ROUND(
            SUM(p95_driver_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p95_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p95_driver_cpu_busy_percent_28d,
        ROUND(
            SUM(p95_worker_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p95_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p95_worker_cpu_busy_percent_7d,
        ROUND(
            SUM(p95_worker_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p95_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p95_worker_cpu_busy_percent_28d,
        ROUND(
            SUM(p95_driver_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p95_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p95_driver_mem_used_percent_7d,
        ROUND(
            SUM(p95_driver_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p95_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p95_driver_mem_used_percent_28d,
        ROUND(
            SUM(p95_worker_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p95_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p95_worker_mem_used_percent_7d,
        ROUND(
            SUM(p95_worker_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p95_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p95_worker_mem_used_percent_28d,
        ROUND(
            SUM(p50_driver_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p50_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p50_driver_cpu_busy_percent_7d,
        ROUND(
            SUM(p50_driver_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p50_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p50_driver_cpu_busy_percent_28d,
        ROUND(
            SUM(p50_worker_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p50_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p50_worker_cpu_busy_percent_7d,
        ROUND(
            SUM(p50_worker_cpu_busy_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p50_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p50_worker_cpu_busy_percent_28d,
        ROUND(
            SUM(p50_driver_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p50_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p50_driver_cpu_wait_percent_7d,
        ROUND(
            SUM(p50_driver_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p50_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p50_driver_cpu_wait_percent_28d,
        ROUND(
            SUM(p50_worker_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p50_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p50_worker_cpu_wait_percent_7d,
        ROUND(
            SUM(p50_worker_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p50_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p50_worker_cpu_wait_percent_28d,
        ROUND(
            SUM(p50_driver_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p50_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p50_driver_mem_used_percent_7d,
        ROUND(
            SUM(p50_driver_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p50_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p50_driver_mem_used_percent_28d,
        ROUND(
            SUM(p50_worker_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p50_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p50_worker_mem_used_percent_7d,
        ROUND(
            SUM(p50_worker_mem_used_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p50_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p50_worker_mem_used_percent_28d,
        ROUND(
            SUM(p95_driver_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p95_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p95_driver_cpu_wait_percent_7d,
        ROUND(
            SUM(p95_driver_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p95_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p95_driver_cpu_wait_percent_28d,
        ROUND(
            SUM(p95_worker_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN p95_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_p95_worker_cpu_wait_percent_7d,
        ROUND(
            SUM(p95_worker_cpu_wait_percent * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN p95_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_p95_worker_cpu_wait_percent_28d,
        ROUND(
            SUM(local_disk_utilization_pct_p95 * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0)) FILTER (WHERE in_7d_window)
                / NULLIF(SUM(CASE WHEN local_disk_utilization_pct_p95 IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END) FILTER (WHERE in_7d_window), 0.0),
            2
        ) AS avg_local_disk_utilization_pct_p95_7d,
        ROUND(
            SUM(local_disk_utilization_pct_p95 * COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0))
                / NULLIF(SUM(CASE WHEN local_disk_utilization_pct_p95 IS NOT NULL THEN COALESCE(CAST(execution_duration_seconds AS DOUBLE), 0.0) ELSE 0.0 END), 0.0),
            2
        ) AS avg_local_disk_utilization_pct_p95_28d
    FROM window_runs
    GROUP BY airflow_dag_id
)
SELECT
    -- --- Keys ---
    wr.airflow_dag_id                                                                        AS airflow_dag_id,
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
    ROUND(SUM(total_dbu_consumed) FILTER (WHERE in_7d_window), 4)                           AS total_dbu_consumed_7d,
    ROUND(SUM(total_dbu_consumed),                                  4)                     AS total_dbu_consumed_28d,
    ROUND(SUM(total_dbu_cost_usd) FILTER (WHERE in_7d_window), 4)                       AS total_dbu_cost_usd_7d,
    ROUND(SUM(total_dbu_cost_usd),                             4)                         AS total_dbu_cost_usd_28d,
    ROUND(
        SUM(total_dbu_cost_usd) FILTER (WHERE in_7d_window)
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        4
    )                                                                                    AS avg_dbu_cost_usd_per_dag_run_7d,
    ROUND(
        SUM(total_dbu_cost_usd) / NULLIF(COUNT(*), 0),
        4
    )                                                                                    AS avg_dbu_cost_usd_per_dag_run_28d,
    ROUND(SUM(total_ec2_cost_usd) FILTER (WHERE in_7d_window), 4)             AS total_ec2_cost_usd_7d,
    ROUND(SUM(total_ec2_cost_usd),                                  4)         AS total_ec2_cost_usd_28d,
    ROUND(SUM(total_ec2_net_cost_usd) FILTER (WHERE in_7d_window), 4)  AS total_ec2_net_cost_usd_7d,
    ROUND(SUM(total_ec2_net_cost_usd), 4)                              AS total_ec2_net_cost_usd_28d,
    ROUND(SUM(total_net_cost_usd) FILTER (WHERE in_7d_window), 4)      AS total_net_cost_usd_7d,
    ROUND(SUM(total_net_cost_usd), 4)                                  AS total_net_cost_usd_28d,
    ROUND(SUM(total_discount_usd) FILTER (WHERE in_7d_window), 4)      AS total_discount_usd_7d,
    ROUND(SUM(total_discount_usd), 4)                                  AS total_discount_usd_28d,
    ROUND(SUM(ec2_spot_hours) FILTER (WHERE in_7d_window), 4)                           AS ec2_spot_hours_7d,
    ROUND(SUM(ec2_spot_hours),                                  4)                     AS ec2_spot_hours_28d,
    ROUND(SUM(ec2_on_demand_hours) FILTER (WHERE in_7d_window), 4)                     AS ec2_on_demand_hours_7d,
    ROUND(SUM(ec2_on_demand_hours),                                  4)               AS ec2_on_demand_hours_28d,
    BOOL_OR(is_ec2_estimated) FILTER (WHERE in_7d_window)                              AS has_ec2_estimate_7d,
    BOOL_OR(is_ec2_estimated)                                                          AS has_ec2_estimate_28d,
    BOOL_OR(ec2_pricing_missing) FILTER (WHERE in_7d_window)                           AS has_ec2_pricing_missing_7d,
    BOOL_OR(ec2_pricing_missing)                                                       AS has_ec2_pricing_missing_28d,
    ROUND(SUM(total_cost_usd) FILTER (WHERE in_7d_window), 4)                            AS total_cost_usd_7d,
    ROUND(SUM(total_cost_usd),                                  4)                     AS total_cost_usd_28d,
    ROUND(
        SUM(total_cost_usd) FILTER (WHERE in_7d_window)
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        4
    )                                                                                    AS avg_total_cost_usd_per_dag_run_7d,
    ROUND(
        SUM(total_cost_usd) / NULLIF(COUNT(*), 0),
        4
    )                                                                                    AS avg_total_cost_usd_per_dag_run_28d,
    ROUND(
        SUM(total_net_cost_usd) FILTER (WHERE in_7d_window)
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        4
    )                                                                  AS avg_net_cost_usd_per_dag_run_7d,
    ROUND(
        SUM(total_net_cost_usd) / NULLIF(COUNT(*), 0),
        4
    )                                                                  AS avg_net_cost_usd_per_dag_run_28d,
    ROUND(
        SUM(total_cost_usd) FILTER (WHERE in_7d_window)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_7d_window) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                    AS total_cost_usd_per_executor_second_7d,
    ROUND(
        SUM(total_cost_usd)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                    AS total_cost_usd_per_executor_second_28d,
    -- --- Volume ---
    COUNT(*) FILTER (WHERE in_7d_window)                                                   AS total_dag_runs_7d,
    COUNT(*)                                                                               AS total_dag_runs_28d,
    SUM(n_databricks_job_runs) FILTER (WHERE in_7d_window)                                 AS total_job_runs_7d,
    SUM(n_databricks_job_runs)                                                           AS total_job_runs_28d,
    SUM(n_task_runs) FILTER (WHERE in_7d_window)                                          AS total_task_runs_7d,
    SUM(n_task_runs)                                                                       AS total_task_runs_28d,
    -- --- Latency ---
    ROUND(AVG(total_duration_seconds) FILTER (WHERE in_7d_window), 2)                   AS avg_total_duration_seconds_7d,
    ROUND(AVG(total_duration_seconds),                                 2)                 AS avg_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.50) FILTER (WHERE in_7d_window)          AS p50_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.50)                                      AS p50_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.95) FILTER (WHERE in_7d_window)          AS p95_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.95)                                      AS p95_total_duration_seconds_28d,
    APPROX_PERCENTILE(total_duration_seconds, 0.99) FILTER (WHERE in_7d_window)          AS p99_total_duration_seconds_7d,
    APPROX_PERCENTILE(total_duration_seconds, 0.99)                                      AS p99_total_duration_seconds_28d,
    ROUND(AVG(execution_duration_seconds) FILTER (WHERE in_7d_window), 2)              AS avg_execution_duration_seconds_7d,
    ROUND(AVG(execution_duration_seconds),                             2)               AS avg_execution_duration_seconds_28d,
    ROUND(AVG(setup_duration_seconds) FILTER (WHERE in_7d_window), 2)                  AS avg_setup_duration_seconds_7d,
    ROUND(AVG(setup_duration_seconds),                                 2)               AS avg_setup_duration_seconds_28d,
    -- --- Startup ---
    APPROX_PERCENTILE(setup_duration_seconds, 0.95) FILTER (WHERE in_7d_window)            AS p95_setup_duration_seconds_7d,
    APPROX_PERCENTILE(setup_duration_seconds, 0.95)                                      AS p95_setup_duration_seconds_28d,
    APPROX_PERCENTILE(pre_init_script_seconds, 0.95) FILTER (WHERE in_7d_window)       AS p95_pre_init_script_seconds_7d,
    APPROX_PERCENTILE(pre_init_script_seconds, 0.95)                                   AS p95_pre_init_script_seconds_28d,
    APPROX_PERCENTILE(init_script_seconds, 0.50) FILTER (WHERE in_7d_window)             AS p50_init_script_seconds_7d,
    APPROX_PERCENTILE(init_script_seconds, 0.50)                                       AS p50_init_script_seconds_28d,
    APPROX_PERCENTILE(init_script_seconds, 0.95) FILTER (WHERE in_7d_window)            AS p95_init_script_seconds_7d,
    APPROX_PERCENTILE(init_script_seconds, 0.95)                                       AS p95_init_script_seconds_28d,
    APPROX_PERCENTILE(post_init_script_seconds, 0.95) FILTER (WHERE in_7d_window)     AS p95_post_init_script_seconds_7d,
    APPROX_PERCENTILE(post_init_script_seconds, 0.95)                                 AS p95_post_init_script_seconds_28d,
    ROUND(
        SUM(init_script_seconds) FILTER (WHERE in_7d_window) / 60.0,
        2
    )                                                                                    AS total_init_minutes_7d,
    ROUND(
        SUM(init_script_seconds) / 60.0,
        2
    )                                                                                    AS total_init_minutes_28d,
    APPROX_PERCENTILE(cluster_startup_seconds, 0.95) FILTER (WHERE in_7d_window)       AS p95_cluster_startup_seconds_7d,
    APPROX_PERCENTILE(cluster_startup_seconds, 0.95)                                   AS p95_cluster_startup_seconds_28d,
    -- --- Reliability ---
    SUM(n_failed_task_runs) FILTER (WHERE in_7d_window)                                AS failed_task_runs_7d,
    SUM(n_failed_task_runs)                                                            AS failed_task_runs_28d,
    ROUND(
        SUM(n_failed_task_runs) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(SUM(n_task_runs) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS error_rate_pct_7d,
    ROUND(
        SUM(n_failed_task_runs) * 100.0 / NULLIF(SUM(n_task_runs), 0),
        2
    )                                                                                    AS error_rate_pct_28d,
    SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window)    AS failed_dag_runs_7d,
    SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END)                                AS failed_dag_runs_28d,
    ROUND(
        SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS failed_dag_run_rate_pct_7d,
    ROUND(
        SUM(CASE WHEN is_any_task_failed THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0),
        2
    )                                                                                    AS failed_dag_run_rate_pct_28d,
    -- --- Cold start ---
    SUM(n_pool_acquisition_slow_tasks) FILTER (WHERE in_7d_window)                     AS cold_start_count_7d,
    SUM(n_pool_acquisition_slow_tasks)                                                 AS cold_start_count_28d,
    ROUND(
        SUM(n_pool_acquisition_slow_tasks) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(SUM(n_task_runs) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS cold_start_rate_pct_7d,
    ROUND(
        SUM(n_pool_acquisition_slow_tasks) * 100.0 / NULLIF(SUM(n_task_runs), 0),
        2
    )                                                                                    AS cold_start_rate_pct_28d,
    ROUND(SUM(n_pool_acquisition_slow_tasks) FILTER (WHERE in_7d_window) / 7.0, 2)       AS cold_starts_per_day_7d,
    ROUND(SUM(n_pool_acquisition_slow_tasks) / 28.0, 2)                                AS cold_starts_per_day_28d,
    -- --- Utilisation ---
    MAX(wu.avg_p95_driver_cpu_busy_percent_7d)                                           AS avg_p95_driver_cpu_busy_percent_7d,
    MAX(wu.avg_p95_driver_cpu_busy_percent_28d)                                          AS avg_p95_driver_cpu_busy_percent_28d,
    MAX(wu.avg_p95_worker_cpu_busy_percent_7d)                                           AS avg_p95_worker_cpu_busy_percent_7d,
    MAX(wu.avg_p95_worker_cpu_busy_percent_28d)                                          AS avg_p95_worker_cpu_busy_percent_28d,
    MAX(wu.avg_p95_driver_mem_used_percent_7d)                                           AS avg_p95_driver_mem_used_percent_7d,
    MAX(wu.avg_p95_driver_mem_used_percent_28d)                                          AS avg_p95_driver_mem_used_percent_28d,
    MAX(wu.avg_p95_worker_mem_used_percent_7d)                                           AS avg_p95_worker_mem_used_percent_7d,
    MAX(wu.avg_p95_worker_mem_used_percent_28d)                                          AS avg_p95_worker_mem_used_percent_28d,
    MAX(wu.avg_p95_driver_cpu_wait_percent_7d)                                           AS avg_p95_driver_cpu_wait_percent_7d,
    MAX(wu.avg_p95_driver_cpu_wait_percent_28d)                                          AS avg_p95_driver_cpu_wait_percent_28d,
    MAX(wu.avg_p95_worker_cpu_wait_percent_7d)                                           AS avg_p95_worker_cpu_wait_percent_7d,
    MAX(wu.avg_p95_worker_cpu_wait_percent_28d)                                          AS avg_p95_worker_cpu_wait_percent_28d,
    MAX(wu.avg_p50_driver_cpu_busy_percent_7d)                                           AS avg_p50_driver_cpu_busy_percent_7d,
    MAX(wu.avg_p50_driver_cpu_busy_percent_28d)                                          AS avg_p50_driver_cpu_busy_percent_28d,
    MAX(wu.avg_p50_worker_cpu_busy_percent_7d)                                           AS avg_p50_worker_cpu_busy_percent_7d,
    MAX(wu.avg_p50_worker_cpu_busy_percent_28d)                                          AS avg_p50_worker_cpu_busy_percent_28d,
    MAX(wu.avg_p50_driver_cpu_wait_percent_7d)                                           AS avg_p50_driver_cpu_wait_percent_7d,
    MAX(wu.avg_p50_driver_cpu_wait_percent_28d)                                          AS avg_p50_driver_cpu_wait_percent_28d,
    MAX(wu.avg_p50_worker_cpu_wait_percent_7d)                                           AS avg_p50_worker_cpu_wait_percent_7d,
    MAX(wu.avg_p50_worker_cpu_wait_percent_28d)                                          AS avg_p50_worker_cpu_wait_percent_28d,
    MAX(wu.avg_p50_driver_mem_used_percent_7d)                                           AS avg_p50_driver_mem_used_percent_7d,
    MAX(wu.avg_p50_driver_mem_used_percent_28d)                                          AS avg_p50_driver_mem_used_percent_28d,
    MAX(wu.avg_p50_worker_mem_used_percent_7d)                                           AS avg_p50_worker_mem_used_percent_7d,
    MAX(wu.avg_p50_worker_mem_used_percent_28d)                                          AS avg_p50_worker_mem_used_percent_28d,
    MAX(wu.avg_local_disk_utilization_pct_p95_7d)                                        AS avg_local_disk_utilization_pct_p95_7d,
    MAX(wu.avg_local_disk_utilization_pct_p95_28d)                                       AS avg_local_disk_utilization_pct_p95_28d,
    -- --- Right-sizing ratios ---
    ROUND(
        MAX(wu.avg_p95_driver_cpu_busy_percent_7d) - MAX(wu.avg_p95_worker_cpu_busy_percent_7d),
        2
    )                                                                                    AS driver_minus_worker_cpu_pp_7d,
    ROUND(
        MAX(wu.avg_p95_driver_cpu_busy_percent_28d) - MAX(wu.avg_p95_worker_cpu_busy_percent_28d),
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
    ROUND(MAX(wu.avg_p95_worker_cpu_busy_percent_7d)  / 100.0, 4)                      AS worker_cpu_utilization_ratio_7d,
    ROUND(MAX(wu.avg_p95_worker_cpu_busy_percent_28d) / 100.0, 4)                      AS worker_cpu_utilization_ratio_28d,
    ROUND(MAX(wu.avg_p95_driver_cpu_busy_percent_7d)  / 100.0, 4)                      AS driver_cpu_utilization_ratio_7d,
    ROUND(MAX(wu.avg_p95_driver_cpu_busy_percent_28d) / 100.0, 4)                      AS driver_cpu_utilization_ratio_28d,
    -- --- Spark / memory / I/O ---
    SUM(total_disk_bytes_spilled) FILTER (WHERE in_7d_window)                          AS total_disk_bytes_spilled_7d,
    SUM(total_disk_bytes_spilled)                                                      AS total_disk_bytes_spilled_28d,
    SUM(total_memory_bytes_spilled) FILTER (WHERE in_7d_window)                         AS total_memory_bytes_spilled_7d,
    SUM(total_memory_bytes_spilled)                                                    AS total_memory_bytes_spilled_28d,
    MAX(max_peak_execution_memory_bytes) FILTER (WHERE in_7d_window)                   AS peak_execution_memory_bytes_7d,
    MAX(max_peak_execution_memory_bytes)                                               AS peak_execution_memory_bytes_28d,
    MAX(max_jvm_heap_bytes) FILTER (WHERE in_7d_window)                                AS peak_jvm_heap_bytes_7d,
    MAX(max_jvm_heap_bytes)                                                            AS peak_jvm_heap_bytes_28d,
    SUM(total_gc_time_ms) FILTER (WHERE in_7d_window)                                 AS total_gc_time_ms_7d,
    SUM(total_gc_time_ms)                                                              AS total_gc_time_ms_28d,
    MAX(max_task_skew_ratio) FILTER (WHERE in_7d_window)                               AS peak_task_skew_ratio_7d,
    MAX(max_task_skew_ratio)                                                           AS peak_task_skew_ratio_28d,
    SUM(total_shuffle_bytes_read) FILTER (WHERE in_7d_window)                          AS total_shuffle_bytes_read_7d,
    SUM(total_shuffle_bytes_read)                                                      AS total_shuffle_bytes_read_28d,
    SUM(total_shuffle_bytes_written) FILTER (WHERE in_7d_window)                     AS total_shuffle_bytes_written_7d,
    SUM(total_shuffle_bytes_written)                                                   AS total_shuffle_bytes_written_28d,
    SUM(total_executor_cpu_time_ms) FILTER (WHERE in_7d_window)                        AS total_executor_cpu_time_ms_7d,
    SUM(total_executor_cpu_time_ms)                                                    AS total_executor_cpu_time_ms_28d,
    SUM(total_output_bytes_written) FILTER (WHERE in_7d_window)                        AS total_output_bytes_written_7d,
    SUM(total_output_bytes_written)                                                    AS total_output_bytes_written_28d,
    SUM(stage_count) FILTER (WHERE in_7d_window)                                       AS total_stage_count_7d,
    SUM(stage_count)                                                                   AS total_stage_count_28d,
    SUM(failed_stage_count) FILTER (WHERE in_7d_window)                                AS total_failed_stage_count_7d,
    SUM(failed_stage_count)                                                            AS total_failed_stage_count_28d,
    ROUND(
        SUM(failed_stage_count) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(SUM(stage_count) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS failed_stage_rate_pct_7d,
    ROUND(
        SUM(failed_stage_count) * 100.0 / NULLIF(SUM(stage_count), 0),
        2
    )                                                                                    AS failed_stage_rate_pct_28d,
    ROUND(
        SUM(total_executor_cpu_time_ms) FILTER (WHERE in_7d_window)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_7d_window) AS DOUBLE), 0),
        4
    )                                                                                    AS executor_cpu_efficiency_ratio_7d,
    ROUND(
        SUM(total_executor_cpu_time_ms)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) AS DOUBLE), 0),
        4
    )                                                                                    AS executor_cpu_efficiency_ratio_28d,
    SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_7d_window)           AS stage_attribution_ambiguous_tasks_7d,
    SUM(n_stage_attribution_ambiguous_task_runs)                                         AS stage_attribution_ambiguous_tasks_28d,
    ROUND(
        SUM(n_stage_attribution_ambiguous_task_runs) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(SUM(n_task_runs) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS stage_attribution_ambiguous_rate_pct_7d,
    ROUND(
        SUM(n_stage_attribution_ambiguous_task_runs) * 100.0 / NULLIF(SUM(n_task_runs), 0),
        2
    )                                                                                    AS stage_attribution_ambiguous_rate_pct_28d,
    -- --- Cluster adoption ---
    ROUND(
        SUM(CASE WHEN is_any_photon THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS photon_run_rate_pct_7d,
    ROUND(
        SUM(CASE WHEN is_any_photon THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0),
        2
    )                                                                                    AS photon_run_rate_pct_28d,
    ROUND(
        SUM(CASE WHEN is_any_pool_backed THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS pool_backed_run_rate_pct_7d,
    ROUND(
        SUM(CASE WHEN is_any_pool_backed THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0),
        2
    )                                                                                    AS pool_backed_run_rate_pct_28d,
    ROUND(
        SUM(CASE WHEN is_any_local_nvme THEN 1 ELSE 0 END) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS local_nvme_run_rate_pct_7d,
    ROUND(
        SUM(CASE WHEN is_any_local_nvme THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0),
        2
    )                                                                                    AS local_nvme_run_rate_pct_28d,
    -- --- Data quality ---
    ROUND(
        SUM(n_task_runs_with_stage_data) FILTER (WHERE in_7d_window) * 100.0
            / NULLIF(SUM(n_task_runs) FILTER (WHERE in_7d_window), 0),
        2
    )                                                                                    AS pct_task_runs_with_stage_data_7d,
    ROUND(
        SUM(n_task_runs_with_stage_data) * 100.0 / NULLIF(SUM(n_task_runs), 0),
        2
    )                                                                                    AS pct_task_runs_with_stage_data_28d,
    -- --- Tail ---
    DATE('{load_start_date}')                                                          AS dt_window_end,
    CURRENT_TIMESTAMP()                                                                  AS ts_load,
    YEAR(DATE('{load_start_date}'))                                                    AS year,
    MONTH(DATE('{load_start_date}'))                                                   AS month,
    DAY(DATE('{load_start_date}'))                                                     AS day
FROM
    window_runs wr
    LEFT JOIN weighted_util wu ON wr.airflow_dag_id = wu.airflow_dag_id
GROUP BY
    wr.airflow_dag_id
