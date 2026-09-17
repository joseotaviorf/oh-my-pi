-- ============================================================================
-- fact_emr_dag_run.sql
--
-- Logical Airflow DAG execution grain rolled up from fact_emr_task_run.
-- One row per (airflow_dag_id, minute bucket of ts_run_started).
--
-- Column names mirror dw_databricks_health.fact_databricks_dag_run so Phase 4
-- can UNION into metric_observability__dags.dag_health. EMR-specific gaps
-- (workspace id, DBR version, stage metrics, startup scripts) are NULL/zero.
-- Cost USD is billed CUR (fact_emr_task_run), not calculated list prices.
-- ============================================================================
SELECT
    -- --- Keys ---
    XXHASH64(
            ftr.airflow_dag_id,
            CAST(UNIX_TIMESTAMP(date_trunc('MINUTE', COALESCE(ftr.ts_run_started, ftr.ts_task_started))) AS STRING)
        )                                                             AS sk_databricks_dag_run,
    CAST(NULL AS BIGINT)                                              AS id_databricks_workspace,
    ftr.airflow_dag_id,
    date_trunc('MINUTE', COALESCE(ftr.ts_run_started, ftr.ts_task_started))
                                                                  AS ts_logical_run_started,
    CAST(DATE_FORMAT(
        DATE(date_trunc('MINUTE', COALESCE(ftr.ts_run_started, ftr.ts_task_started))),
        'yyyyMMdd'
    ) AS INT)                                                       AS sk_dag_run_started_date,
    -- --- Governance ---
    FIRST(ftr.team_owner     IGNORE NULLS)                        AS team_owner,
    FIRST(ftr.cost_center    IGNORE NULLS)                        AS cost_center,
    FIRST(ftr.ecosystem      IGNORE NULLS)                        AS ecosystem,
    FIRST(ftr.environment    IGNORE NULLS)                        AS environment,
    FIRST(ftr.provisioner    IGNORE NULLS)                        AS provisioner,
    MIN_BY(
        ftr.cost_cohort,
        CASE ftr.cost_cohort
            WHEN 'quintoml_wonka' THEN 1
            WHEN 'cdp'            THEN 2
            WHEN 'tech_platform'  THEN 3
            WHEN 'bietlejuice'    THEN 4
            ELSE 5
        END
    )                                                             AS cost_cohort,
    FIRST(ftr.data_classification IGNORE NULLS)                 AS data_classification,
    -- --- Cluster profile ---
    MAX_BY(ftr.driver_node_type, ftr.total_cost_usd)             AS driver_node_type,
    MAX_BY(ftr.worker_node_type, ftr.total_cost_usd)             AS worker_node_type,
    MAX_BY(ftr.worker_count, ftr.total_cost_usd)                 AS worker_count,
    MAX(ftr.peak_concurrent_workers)                             AS peak_concurrent_workers,
    MAX_BY(ftr.cluster_name, ftr.total_cost_usd)                 AS primary_cluster_name,
    MAX_BY(ftr.cluster_source, ftr.total_cost_usd)               AS primary_cluster_source,
    MAX_BY(ftr.dbr_version, ftr.total_cost_usd)                  AS primary_dbr_version,
    MAX_BY(ftr.min_autoscale_workers, ftr.total_cost_usd)        AS primary_min_autoscale_workers,
    MAX_BY(ftr.max_autoscale_workers, ftr.total_cost_usd)        AS primary_max_autoscale_workers,
    MAX_BY(ftr.run_type, ftr.total_cost_usd)                     AS primary_run_type,
    -- --- Cost ---
    CAST(ROUND(SUM(ftr.total_dbu_consumed), 4) AS DECIMAL(25, 4)) AS total_dbu_consumed,
    CAST(ROUND(SUM(ftr.total_dbu_cost_usd), 4) AS DECIMAL(37, 4)) AS total_dbu_cost_usd,
    CAST(ROUND(SUM(ftr.total_dbu_list_cost_usd), 4) AS DECIMAL(37, 4))
                                                                  AS total_dbu_list_cost_usd,
    CAST(ROUND(SUM(ftr.total_ec2_cost_usd), 4) AS DECIMAL(38, 4))
                                                                  AS total_ec2_cost_usd,
    CAST(ROUND(SUM(ftr.total_ebs_cost_usd), 4) AS DECIMAL(38, 4))
                                                                  AS total_ebs_cost_usd,
    CAST(ROUND(SUM(ftr.total_emr_fee_cost_usd), 4) AS DECIMAL(38, 4))
                                                                  AS total_emr_fee_cost_usd,
    CAST(ROUND(SUM(ftr.ec2_spot_hours), 4) AS DECIMAL(38, 4))   AS ec2_spot_hours,
    CAST(ROUND(SUM(ftr.ec2_on_demand_hours), 4) AS DECIMAL(38, 4))
                                                                  AS ec2_on_demand_hours,
    CASE
        WHEN BOOL_OR(ftr.cost_source = 'missing') THEN 'missing'
        WHEN BOOL_OR(ftr.cost_source = 'cur_partial') THEN 'cur_partial'
        WHEN BOOL_OR(ftr.cost_source = 'cur') THEN 'cur'
        ELSE 'missing'
    END                                                             AS cost_source,
    CAST(ROUND(SUM(ftr.total_cost_usd), 4) AS DECIMAL(38, 4))     AS total_cost_usd,
    CAST(ROUND(SUM(ftr.total_ec2_net_cost_usd), 4) AS DECIMAL(38, 4))
                                                                  AS total_ec2_net_cost_usd,
    CAST(ROUND(SUM(ftr.total_ebs_net_cost_usd), 4) AS DECIMAL(38, 4))
                                                                  AS total_ebs_net_cost_usd,
    CAST(ROUND(SUM(ftr.total_emr_fee_net_cost_usd), 4) AS DECIMAL(38, 4))
                                                                  AS total_emr_fee_net_cost_usd,
    CAST(ROUND(SUM(ftr.total_net_cost_usd), 4) AS DECIMAL(38, 4))
                                                                  AS total_net_cost_usd,
    CAST(ROUND(SUM(ftr.total_discount_usd), 4) AS DECIMAL(38, 4))
                                                                  AS total_discount_usd,
    FIRST(ftr.dbu_pricing_sku IGNORE NULLS)                       AS dbu_pricing_sku,
    FIRST(ftr.dbu_rate_usd   IGNORE NULLS)                        AS dbu_rate_usd,
    -- --- Volume & failure counts ---
    COUNT(DISTINCT ftr.id_emr_cluster)                              AS n_databricks_job_runs,
    COUNT(DISTINCT CASE WHEN ftr.is_failed THEN ftr.id_emr_cluster END)
                                                                  AS n_failed_databricks_job_runs,
    COUNT(*)                                                        AS n_task_runs,
    SUM(CASE WHEN ftr.is_failed THEN 1 ELSE 0 END)                  AS n_failed_task_runs,
    CAST(0 AS BIGINT)                                               AS n_task_runs_with_stage_data,
    SUM(CASE WHEN ftr.is_pool_acquisition_slow THEN 1 ELSE 0 END) AS n_pool_acquisition_slow_tasks,
    SUM(CASE WHEN ftr.is_stage_attribution_ambiguous THEN 1 ELSE 0 END)
                                                                  AS n_stage_attribution_ambiguous_task_runs,
    -- --- Latency / startup ---
    BIGINT(
        UNIX_TIMESTAMP(MAX(ftr.ts_task_ended)) - UNIX_TIMESTAMP(MIN(ftr.ts_task_started))
    )                                                               AS total_wall_clock_seconds,
    BIGINT(SUM(ftr.execution_duration_seconds))                     AS total_execution_duration_seconds,
    BIGINT(SUM(ftr.setup_duration_seconds))                         AS total_setup_duration_seconds,
    MAX(ftr.pre_init_script_seconds)                                AS max_pre_init_script_seconds,
    MAX(ftr.init_script_seconds)                                    AS max_init_script_seconds,
    MAX(ftr.post_init_script_seconds)                               AS max_post_init_script_seconds,
    MAX(ftr.cluster_startup_seconds)                                AS max_cluster_startup_seconds,
    -- --- Utilisation ---
    ROUND(
        SUM(ftr.p50_driver_cpu_busy_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p50_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p50_driver_cpu_busy_percent,
    ROUND(
        SUM(ftr.p95_driver_cpu_busy_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p95_driver_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_driver_cpu_busy_percent,
    ROUND(
        SUM(ftr.p50_driver_cpu_wait_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p50_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p50_driver_cpu_wait_percent,
    ROUND(
        SUM(ftr.p95_driver_cpu_wait_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p95_driver_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_driver_cpu_wait_percent,
    ROUND(
        SUM(ftr.p50_driver_mem_used_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p50_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p50_driver_mem_used_percent,
    ROUND(
        SUM(ftr.p95_driver_mem_used_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p95_driver_mem_used_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_driver_mem_used_percent,
    ROUND(
        SUM(ftr.p50_worker_cpu_busy_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p50_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p50_worker_cpu_busy_percent,
    ROUND(
        SUM(ftr.p95_worker_cpu_busy_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p95_worker_cpu_busy_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_worker_cpu_busy_percent,
    ROUND(
        SUM(ftr.p50_worker_cpu_wait_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p50_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p50_worker_cpu_wait_percent,
    ROUND(
        SUM(ftr.p95_worker_cpu_wait_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p95_worker_cpu_wait_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_worker_cpu_wait_percent,
    ROUND(
        SUM(ftr.p50_worker_mem_used_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p50_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p50_worker_mem_used_percent,
    ROUND(
        SUM(ftr.p95_worker_mem_used_percent * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.p95_worker_mem_used_percent IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_p95_worker_mem_used_percent,
    ROUND(
        SUM(ftr.local_disk_utilization_pct_p95 * COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)))
            / NULLIF(SUM(CASE WHEN ftr.local_disk_utilization_pct_p95 IS NOT NULL THEN COALESCE(CAST(ftr.execution_duration_seconds AS DOUBLE), CAST(0 AS DOUBLE)) ELSE CAST(0 AS DOUBLE) END), CAST(0 AS DOUBLE)),
        2
    )                                                               AS weighted_avg_local_disk_utilization_pct_p95,
    -- --- Spark metrics (NULL / zero for EMR v1) ---
    CAST(NULL AS BIGINT)                                          AS stage_count,
    CAST(NULL AS BIGINT)                                          AS failed_stage_count,
    CAST(NULL AS BIGINT)                                          AS spark_app_count,
    CAST(NULL AS BIGINT)                                          AS total_executor_run_time_ms,
    CAST(NULL AS BIGINT)                                          AS total_executor_cpu_time_ms,
    CAST(NULL AS BIGINT)                                          AS total_disk_bytes_spilled,
    CAST(NULL AS BIGINT)                                          AS total_memory_bytes_spilled,
    CAST(NULL AS BIGINT)                                          AS total_input_bytes_read,
    CAST(NULL AS BIGINT)                                          AS total_output_bytes_written,
    CAST(NULL AS BIGINT)                                          AS max_peak_execution_memory_bytes,
    CAST(NULL AS BIGINT)                                          AS max_jvm_heap_bytes,
    CAST(NULL AS BIGINT)                                          AS total_gc_time_ms,
    CAST(NULL AS BIGINT)                                          AS max_task_run_time_ms,
    CAST(NULL AS DOUBLE)                                          AS max_task_skew_ratio,
    CAST(NULL AS BIGINT)                                          AS total_shuffle_bytes_read,
    CAST(NULL AS BIGINT)                                          AS total_shuffle_bytes_written,
    CAST(NULL AS STRING)                                          AS last_stage_failure_reason,
    -- --- Booleans ---
    MAX(CASE WHEN ftr.is_failed THEN 1 ELSE 0 END) >= 1           AS is_any_task_failed,
    MAX(CASE WHEN ftr.is_success THEN 1 ELSE 0 END) >= 1          AS is_any_task_success,
    MAX(CASE WHEN ftr.is_failed THEN 1 ELSE 0 END) >= 1           AS is_any_databricks_run_failed,
    BOOL_OR(ftr.is_photon)                                        AS is_any_photon,
    BOOL_OR(ftr.is_pool_backed)                                  AS is_any_pool_backed,
    BOOL_OR(ftr.has_local_nvme)                                  AS is_any_local_nvme,
    BOOL_OR(ftr.is_sensitive_data)                               AS is_any_sensitive_data,
    BOOL_OR(ftr.is_stage_attribution_ambiguous)                  AS is_any_stage_attribution_ambiguous,
    BOOL_OR(ftr.is_job_on_interactive)                           AS is_job_on_interactive,
    BOOL_OR(ftr.dbu_negotiated_price_missing)                    AS dbu_negotiated_price_missing,
    -- --- Dates / timestamps / partitions ---
    DATE(date_trunc('MINUTE', COALESCE(ftr.ts_run_started, ftr.ts_task_started)))
                                                                  AS dt_dag_run_started,
    MIN(COALESCE(ftr.ts_run_started, ftr.ts_task_started))        AS ts_run_started_min,
    MAX(COALESCE(ftr.ts_run_ended, ftr.ts_task_ended))            AS ts_run_ended_max,
    CURRENT_TIMESTAMP()                                           AS ts_load,
    YEAR(DATE(date_trunc('MINUTE', COALESCE(ftr.ts_run_started, ftr.ts_task_started))))
                                                                  AS year,
    MONTH(DATE(date_trunc('MINUTE', COALESCE(ftr.ts_run_started, ftr.ts_task_started))))
                                                                  AS month,
    DAY(DATE(date_trunc('MINUTE', COALESCE(ftr.ts_run_started, ftr.ts_task_started))))
                                                                  AS day
FROM
    dw_emr_health.fact_emr_task_run AS ftr
WHERE
    DATE(ftr.dt_task_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND ftr.airflow_dag_id IS NOT NULL
GROUP BY
    ftr.airflow_dag_id,
    date_trunc('MINUTE', COALESCE(ftr.ts_run_started, ftr.ts_task_started))
