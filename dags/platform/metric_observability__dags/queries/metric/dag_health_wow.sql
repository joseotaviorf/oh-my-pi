-- ============================================================================
-- dag_health_wow.sql
--
-- Week-over-week comparison for Databricks DAG observability: each metric is
-- computed over the trailing 7 days ending on load_start_date ("current") and
-- the prior 7 days ("previous"), plus percent change. One row per
-- (airflow_dag_id, dt_window_end). Reads exclusively from
-- dw_databricks_health.fact_databricks_task_run.
--
-- Window (14 calendar days):
--   previous_7d: load_start_date - 13 days through load_start_date - 7 days
--   current_7d:    load_start_date - 6 days through load_start_date
--
-- change_pct: ROUND((current - previous) / NULLIF(previous, 0) * 100, 2).
-- Cost blends use system DBU USD + deduped Overwatch EC2 USD per cluster-day.
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
        ts_run_started,
        dbu_consumed,
        cost_usd_estimate,
        total_ec2_cost_overwatch_usd,
        total_dbu_cost_overwatch_usd,
        total_cost_overwatch_usd,
        total_duration_seconds,
        total_executor_run_time_ms,
        is_failed,
        p95_driver_cpu_busy_percent,
        p95_worker_cpu_busy_percent,
        p95_driver_mem_used_percent,
        p95_worker_mem_used_percent,
        dt_task_started >= DATE('{load_start_date}') - INTERVAL 6 DAYS           AS in_current_7d,
        dt_task_started BETWEEN DATE('{load_start_date}') - INTERVAL 13 DAYS
            AND DATE('{load_start_date}') - INTERVAL 7 DAYS                      AS in_previous_7d,
        ROW_NUMBER() OVER (
            PARTITION BY id_cluster, dt_task_started
            ORDER BY ts_task_started, id_databricks_task_run
        ) = 1                                                                       AS is_first_task_of_cluster_day,
        id_cluster,
        dt_task_started,
        ts_task_started
    FROM
        dw_databricks_health.fact_databricks_task_run
    WHERE
        dt_task_started >= DATE('{load_start_date}') - INTERVAL 13 DAYS
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

    COUNT(DISTINCT IF(in_current_7d, date_trunc('MINUTE', ts_run_started), NULL))          AS total_dag_runs_current_7d,
    COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL))          AS total_dag_runs_previous_7d,
    ROUND(
        (
            CAST(COUNT(DISTINCT IF(in_current_7d, date_trunc('MINUTE', ts_run_started), NULL)) AS DOUBLE)
            - CAST(COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL)) AS DOUBLE)
        ) * 100.0
            / NULLIF(CAST(COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL)) AS DOUBLE), 0),
        2
    )                                                                                      AS total_dag_runs_change_pct,

    COUNT(DISTINCT IF(in_current_7d, id_databricks_run, NULL))                           AS total_job_runs_current_7d,
    COUNT(DISTINCT IF(in_previous_7d, id_databricks_run, NULL))                         AS total_job_runs_previous_7d,
    ROUND(
        (
            CAST(COUNT(DISTINCT IF(in_current_7d, id_databricks_run, NULL)) AS DOUBLE)
            - CAST(COUNT(DISTINCT IF(in_previous_7d, id_databricks_run, NULL)) AS DOUBLE)
        ) * 100.0
            / NULLIF(CAST(COUNT(DISTINCT IF(in_previous_7d, id_databricks_run, NULL)) AS DOUBLE), 0),
        2
    )                                                                                      AS total_job_runs_change_pct,

    COUNT(DISTINCT IF(in_current_7d, id_databricks_task_run, NULL))                     AS total_task_runs_current_7d,
    COUNT(DISTINCT IF(in_previous_7d, id_databricks_task_run, NULL))                     AS total_task_runs_previous_7d,
    ROUND(
        (
            CAST(COUNT(DISTINCT IF(in_current_7d, id_databricks_task_run, NULL)) AS DOUBLE)
            - CAST(COUNT(DISTINCT IF(in_previous_7d, id_databricks_task_run, NULL)) AS DOUBLE)
        ) * 100.0
            / NULLIF(CAST(COUNT(DISTINCT IF(in_previous_7d, id_databricks_task_run, NULL)) AS DOUBLE), 0),
        2
    )                                                                                      AS total_task_runs_change_pct,

    ROUND(SUM(dbu_consumed) FILTER (WHERE in_current_7d),  4)                             AS total_dbu_consumed_current_7d,
    ROUND(SUM(dbu_consumed) FILTER (WHERE in_previous_7d), 4)                             AS total_dbu_consumed_previous_7d,
    ROUND(
        (
            SUM(dbu_consumed) FILTER (WHERE in_current_7d)
            - SUM(dbu_consumed) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(dbu_consumed) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_dbu_consumed_change_pct,

    ROUND(SUM(cost_usd_estimate) FILTER (WHERE in_current_7d),  4)                      AS total_dbu_cost_usd_current_7d,
    ROUND(SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d), 4)                      AS total_dbu_cost_usd_previous_7d,
    ROUND(
        (
            SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
            - SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_dbu_cost_usd_change_pct,

    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL))
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_ec2_cost_overwatch_usd_current_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL))
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_ec2_cost_overwatch_usd_previous_7d,
    ROUND(
        (
            SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_current_7d)
            - SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_ec2_cost_overwatch_usd_change_pct,

    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
            + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_cost_blended_usd_current_7d,
    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
            + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_cost_blended_usd_previous_7d,
    ROUND(
        (
            SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
                + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_current_7d)
            - (
                SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                    + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d)
            )
        ) * 100.0
            / NULLIF(
                SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                    + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d),
                0
            ),
        2
    )                                                                                      AS total_cost_blended_usd_change_pct,

    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
            / NULLIF(COUNT(DISTINCT IF(in_current_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0),
        4
    )                                                                                      AS avg_dbu_cost_usd_per_dag_run_current_7d,
    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
            / NULLIF(COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0),
        4
    )                                                                                      AS avg_dbu_cost_usd_per_dag_run_previous_7d,
    ROUND(
        (
            SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
                / NULLIF(COUNT(DISTINCT IF(in_current_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0)
            - SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                / NULLIF(COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0)
        ) * 100.0
            / NULLIF(
                SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                    / NULLIF(COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0),
                0
            ),
        2
    )                                                                                      AS avg_dbu_cost_usd_per_dag_run_change_pct,

    ROUND(
        (
            SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
                + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_current_7d)
        )
            / NULLIF(COUNT(DISTINCT IF(in_current_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0),
        4
    )                                                                                      AS avg_cost_blended_usd_per_dag_run_current_7d,
    ROUND(
        (
            SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d)
        )
            / NULLIF(COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0),
        4
    )                                                                                      AS avg_cost_blended_usd_per_dag_run_previous_7d,
    ROUND(
        (
            (
                SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
                    + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_current_7d)
            )
                / NULLIF(COUNT(DISTINCT IF(in_current_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0)
            - (
                (
                    SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                        + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d)
                )
                    / NULLIF(COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0)
            )
        ) * 100.0
            / NULLIF(
                (
                    SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                        + SUM(IF(is_first_task_of_cluster_day, total_ec2_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d)
                )
                    / NULLIF(COUNT(DISTINCT IF(in_previous_7d, date_trunc('MINUTE', ts_run_started), NULL)), 0),
                0
            ),
        2
    )                                                                                      AS avg_cost_blended_usd_per_dag_run_change_pct,

    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_current_7d) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                      AS cost_efficiency_usd_per_executor_second_current_7d,
    ROUND(
        SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
            / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0),
        6
    )                                                                                      AS cost_efficiency_usd_per_executor_second_previous_7d,
    ROUND(
        (
            SUM(cost_usd_estimate) FILTER (WHERE in_current_7d)
                / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_current_7d) AS DOUBLE) / 1000.0, 0)
            - SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0)
        ) * 100.0
            / NULLIF(
                SUM(cost_usd_estimate) FILTER (WHERE in_previous_7d)
                    / NULLIF(CAST(SUM(total_executor_run_time_ms) FILTER (WHERE in_previous_7d) AS DOUBLE) / 1000.0, 0),
                0
            ),
        2
    )                                                                                      AS cost_efficiency_usd_per_executor_second_change_pct,

    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_dbu_cost_overwatch_usd, NULL))
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_dbu_cost_overwatch_usd_current_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_dbu_cost_overwatch_usd, NULL))
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_dbu_cost_overwatch_usd_previous_7d,
    ROUND(
        (
            SUM(IF(is_first_task_of_cluster_day, total_dbu_cost_overwatch_usd, NULL)) FILTER (WHERE in_current_7d)
            - SUM(IF(is_first_task_of_cluster_day, total_dbu_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(IF(is_first_task_of_cluster_day, total_dbu_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_dbu_cost_overwatch_usd_change_pct,

    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_cost_overwatch_usd, NULL))
            FILTER (WHERE in_current_7d),
        4
    )                                                                                      AS total_cost_overwatch_usd_current_7d,
    ROUND(
        SUM(IF(is_first_task_of_cluster_day, total_cost_overwatch_usd, NULL))
            FILTER (WHERE in_previous_7d),
        4
    )                                                                                      AS total_cost_overwatch_usd_previous_7d,
    ROUND(
        (
            SUM(IF(is_first_task_of_cluster_day, total_cost_overwatch_usd, NULL)) FILTER (WHERE in_current_7d)
            - SUM(IF(is_first_task_of_cluster_day, total_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d)
        ) * 100.0
            / NULLIF(SUM(IF(is_first_task_of_cluster_day, total_cost_overwatch_usd, NULL)) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS total_cost_overwatch_usd_change_pct,

    ROUND(AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_current_7d),  2)             AS avg_p95_worker_cpu_busy_percent_current_7d,
    ROUND(AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_previous_7d), 2)             AS avg_p95_worker_cpu_busy_percent_previous_7d,
    ROUND(
        (
            AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_current_7d)
            - AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(AVG(p95_worker_cpu_busy_percent) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_worker_cpu_busy_percent_change_pct,

    ROUND(AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_current_7d),  2)             AS avg_p95_driver_cpu_busy_percent_current_7d,
    ROUND(AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_previous_7d), 2)             AS avg_p95_driver_cpu_busy_percent_previous_7d,
    ROUND(
        (
            AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_current_7d)
            - AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(AVG(p95_driver_cpu_busy_percent) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_driver_cpu_busy_percent_change_pct,

    ROUND(AVG(p95_worker_mem_used_percent) FILTER (WHERE in_current_7d),  2)             AS avg_p95_worker_mem_used_percent_current_7d,
    ROUND(AVG(p95_worker_mem_used_percent) FILTER (WHERE in_previous_7d), 2)             AS avg_p95_worker_mem_used_percent_previous_7d,
    ROUND(
        (
            AVG(p95_worker_mem_used_percent) FILTER (WHERE in_current_7d)
            - AVG(p95_worker_mem_used_percent) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(AVG(p95_worker_mem_used_percent) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_worker_mem_used_percent_change_pct,

    ROUND(AVG(p95_driver_mem_used_percent) FILTER (WHERE in_current_7d),  2)             AS avg_p95_driver_mem_used_percent_current_7d,
    ROUND(AVG(p95_driver_mem_used_percent) FILTER (WHERE in_previous_7d), 2)             AS avg_p95_driver_mem_used_percent_previous_7d,
    ROUND(
        (
            AVG(p95_driver_mem_used_percent) FILTER (WHERE in_current_7d)
            - AVG(p95_driver_mem_used_percent) FILTER (WHERE in_previous_7d)
        ) * 100.0 / NULLIF(AVG(p95_driver_mem_used_percent) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS avg_p95_driver_mem_used_percent_change_pct,

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
        SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0),
        2
    )                                                                                      AS error_rate_pct_current_7d,
    ROUND(
        SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
        2
    )                                                                                      AS error_rate_pct_previous_7d,
    ROUND(
        (
            SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_current_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_current_7d), 0)
            - SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0)
        )
            / NULLIF(
                SUM(CASE WHEN is_failed THEN 1 ELSE 0 END) FILTER (WHERE in_previous_7d) * 100.0
                    / NULLIF(COUNT(*) FILTER (WHERE in_previous_7d), 0),
                0
            )
            * 100.0,
        2
    )                                                                                      AS error_rate_pct_change_pct,

    DATE('{load_start_date}')                                                              AS dt_window_end,
    CURRENT_TIMESTAMP()                                                                    AS ts_load,
    YEAR(DATE('{load_start_date}'))                                                        AS year,
    MONTH(DATE('{load_start_date}'))                                                       AS month,
    DAY(DATE('{load_start_date}'))                                                         AS day

FROM
    window_runs
GROUP BY
    airflow_dag_id
