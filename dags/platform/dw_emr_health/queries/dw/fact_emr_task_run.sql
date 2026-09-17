-- ============================================================================
-- fact_emr_task_run.sql
--
-- Per EMR step health fact joining datalake_emr_health.emr_dag_task_spine with
-- datalake_emr_health.daily_emr_cluster_cost (billed CUR USD) and
-- datalake_emr_health.daily_emr_cluster_health (CloudWatch utilisation).
--
-- Grain: one row per (id_emr_cluster, id_emr_step) for matched Airflow steps.
--
-- Attribution: for each cluster-day overlapping the step window, allocate
-- billed EC2/EBS/fee USD, CUR usage hours, and CloudWatch utilisation by the
-- step's share of total step overlap seconds on that cluster-day.
--
-- DBU columns are zeroed; Spark stage metrics are NULL (v1 — no event logs).
-- ============================================================================
WITH step_spine AS (
    SELECT
        spine.airflow_dag_id,
        spine.airflow_run_id,
        spine.airflow_task_id,
        spine.id_emr_cluster,
        spine.id_emr_step,
        spine.ts_step_started,
        COALESCE(spine.ts_step_ended, spine.ts_cluster_ended, spine.ts_step_started)
                                                           AS ts_step_ended,
        spine.ts_cluster_started,
        spine.ts_cluster_ended,
        spine.step_state,
        spine.match_confidence,
        DATE(spine.ts_step_started)                        AS dt_step_started
    FROM
        datalake_emr_health.emr_dag_task_spine AS spine
    WHERE
        DATE(spine.ts_step_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND spine.match_confidence IN (
            'tag_and_name', 'tag_only', 'name_only',
            'synthetic', 'exact_event'
        )
        AND spine.airflow_dag_id IS NOT NULL
),
step_with_seconds AS (
    SELECT
        s.*,
        GREATEST(
            CAST(unix_timestamp(s.ts_step_ended) AS BIGINT)
            - CAST(unix_timestamp(s.ts_step_started) AS BIGINT),
            CAST(0 AS BIGINT)
        )                                                  AS step_seconds
    FROM
        step_spine AS s
),
step_cluster_day_overlap AS (
    SELECT
        s.airflow_dag_id,
        s.airflow_run_id,
        s.airflow_task_id,
        s.id_emr_cluster,
        s.id_emr_step,
        dec_days.dt_cluster_run,
        GREATEST(
            CAST(0 AS BIGINT),
            CAST(
                unix_timestamp(
                    LEAST(s.ts_step_ended, CAST(DATE_ADD(dec_days.dt_cluster_run, 1) AS TIMESTAMP))
                ) AS BIGINT
            )
            - CAST(
                unix_timestamp(
                    GREATEST(s.ts_step_started, CAST(dec_days.dt_cluster_run AS TIMESTAMP))
                ) AS BIGINT
            )
        )                                                  AS overlap_seconds
    FROM
        step_with_seconds AS s
    INNER JOIN
        datalake_emr_health.daily_emr_cluster_cost AS dec_days
            ON  dec_days.id_emr_cluster = s.id_emr_cluster
            AND dec_days.dt_cluster_run BETWEEN DATE(s.ts_step_started) AND DATE(s.ts_step_ended)
),
cluster_day_overlap_totals AS (
    SELECT
        id_emr_cluster,
        dt_cluster_run,
        SUM(overlap_seconds)                               AS cluster_day_total_overlap_seconds
    FROM
        step_cluster_day_overlap
    GROUP BY
        id_emr_cluster, dt_cluster_run
),
step_dch_prorated AS (
    SELECT
        scdo.airflow_dag_id,
        scdo.airflow_run_id,
        scdo.airflow_task_id,
        scdo.id_emr_cluster,
        scdo.id_emr_step,
        SUM(
            dec.total_ec2_cost_usd
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS total_ec2_cost_usd,
        SUM(
            dec.total_ebs_cost_usd
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS total_ebs_cost_usd,
        SUM(
            dec.total_emr_fee_cost_usd
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS total_emr_fee_cost_usd,
        SUM(
            dec.ec2_spot_hours
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS ec2_spot_hours,
        SUM(
            dec.ec2_on_demand_hours
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS ec2_on_demand_hours,
        SUM(
            dec.total_ec2_net_cost_usd
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS total_ec2_net_cost_usd,
        SUM(
            dec.total_ebs_net_cost_usd
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS total_ebs_net_cost_usd,
        SUM(
            dec.total_emr_fee_net_cost_usd
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS total_emr_fee_net_cost_usd,
        SUM(
            dec.total_discount_usd
            * (
                CAST(scdo.overlap_seconds AS DOUBLE)
                / NULLIF(CAST(cdot.cluster_day_total_overlap_seconds AS DOUBLE), 0)
            )
        )                                                  AS total_discount_usd,
        MAX(dec.tag_owner)                                 AS team_owner,
        MAX(dec.tag_cost_center)                           AS cost_center,
        MAX(dec.tag_ecosystem)                             AS ecosystem,
        MAX(dec.tag_environment)                           AS environment,
        MAX(dec.tag_data_classification)                   AS data_classification,
        MAX(dec.tag_sensitive_data)                        AS tag_sensitive_data,
        CASE
            WHEN MAX(CASE WHEN COALESCE(dec.cost_source, 'missing') = 'missing' THEN 1 ELSE 0 END) = 1
                THEN 'missing'
            WHEN MAX(CASE WHEN dec.cost_source = 'cur_partial' THEN 1 ELSE 0 END) = 1
                THEN 'cur_partial'
            WHEN MAX(CASE WHEN dec.cost_source = 'cur' THEN 1 ELSE 0 END) = 1
                THEN 'cur'
            ELSE 'missing'
        END                                                AS cost_source
    FROM
        step_cluster_day_overlap AS scdo
    LEFT JOIN
        datalake_emr_health.daily_emr_cluster_cost AS dec
            ON  dec.id_emr_cluster = scdo.id_emr_cluster
            AND dec.dt_cluster_run  = scdo.dt_cluster_run
    INNER JOIN
        cluster_day_overlap_totals AS cdot
            ON  cdot.id_emr_cluster = scdo.id_emr_cluster
            AND cdot.dt_cluster_run = scdo.dt_cluster_run
    GROUP BY
        scdo.airflow_dag_id,
        scdo.airflow_run_id,
        scdo.airflow_task_id,
        scdo.id_emr_cluster,
        scdo.id_emr_step
),
step_dch_health AS (
    SELECT
        scdo.airflow_dag_id,
        scdo.airflow_run_id,
        scdo.airflow_task_id,
        scdo.id_emr_cluster,
        scdo.id_emr_step,
        MAX(dch.worker_count)                              AS peak_concurrent_workers,
        ROUND(
            SUM(dch.p50_master_cpu_percent * CAST(scdo.overlap_seconds AS DOUBLE))
                / NULLIF(SUM(CAST(scdo.overlap_seconds AS DOUBLE)), 0),
            2
        )                                                  AS p50_driver_cpu_busy_percent,
        ROUND(
            SUM(dch.p95_master_cpu_percent * CAST(scdo.overlap_seconds AS DOUBLE))
                / NULLIF(SUM(CAST(scdo.overlap_seconds AS DOUBLE)), 0),
            2
        )                                                  AS p95_driver_cpu_busy_percent,
        ROUND(
            SUM(dch.p50_worker_cpu_percent * CAST(scdo.overlap_seconds AS DOUBLE))
                / NULLIF(SUM(CAST(scdo.overlap_seconds AS DOUBLE)), 0),
            2
        )                                                  AS p50_worker_cpu_busy_percent,
        ROUND(
            SUM(dch.p95_worker_cpu_percent * CAST(scdo.overlap_seconds AS DOUBLE))
                / NULLIF(SUM(CAST(scdo.overlap_seconds AS DOUBLE)), 0),
            2
        )                                                  AS p95_worker_cpu_busy_percent,
        ROUND(
            SUM(dch.p50_yarn_memory_used_percent * CAST(scdo.overlap_seconds AS DOUBLE))
                / NULLIF(SUM(CAST(scdo.overlap_seconds AS DOUBLE)), 0),
            2
        )                                                  AS p50_worker_mem_used_percent,
        ROUND(
            SUM(dch.p95_yarn_memory_used_percent * CAST(scdo.overlap_seconds AS DOUBLE))
                / NULLIF(SUM(CAST(scdo.overlap_seconds AS DOUBLE)), 0),
            2
        )                                                  AS p95_worker_mem_used_percent,
        MAX_BY(dch.cluster_name, scdo.overlap_seconds)     AS cluster_name,
        MAX_BY(dch.master_instance_type, scdo.overlap_seconds)
                                                           AS driver_node_type,
        MAX_BY(dch.worker_instance_type, scdo.overlap_seconds)
                                                           AS worker_node_type,
        MAX(dch.worker_count)                              AS worker_count
    FROM
        step_cluster_day_overlap AS scdo
    INNER JOIN
        datalake_emr_health.daily_emr_cluster_health AS dch
            ON  dch.id_emr_cluster = scdo.id_emr_cluster
            AND dch.dt_cluster_run  = scdo.dt_cluster_run
    GROUP BY
        scdo.airflow_dag_id,
        scdo.airflow_run_id,
        scdo.airflow_task_id,
        scdo.id_emr_cluster,
        scdo.id_emr_step
),

final AS (
SELECT
    XXHASH64(s.id_emr_cluster, s.id_emr_step)                      AS sk_emr_task_run,
    XXHASH64(s.id_emr_cluster)                                     AS sk_emr_cluster,
    XXHASH64(s.airflow_dag_id, s.airflow_run_id)                   AS sk_emr_run,
    CAST(DATE_FORMAT(s.dt_step_started, 'yyyyMMdd') AS INT)        AS sk_step_started_date,

    s.id_emr_cluster,
    s.id_emr_step,
    s.airflow_dag_id,
    s.airflow_run_id,
    s.airflow_task_id,

  -- Governance: lifted from daily_emr_cluster_cost tags; cohort still derives from dim_cost_cohort.
    dch_pro.team_owner,
    dch_pro.cost_center,
    dch_pro.ecosystem,
    dch_pro.environment,
    dch_pro.data_classification,
    'emr'                                                          AS provisioner,

    dch_health.cluster_name,
    CAST(NULL AS STRING)                                           AS cluster_source,
    dch_health.driver_node_type,
    dch_health.worker_node_type,
    CAST(NULL AS STRING)                                           AS dbr_version,
    dch_health.worker_count,
    CAST(NULL AS INT)                                              AS min_autoscale_workers,
    CAST(NULL AS INT)                                              AS max_autoscale_workers,
    dch_health.peak_concurrent_workers,
    CAST(NULL AS STRING)                                           AS run_type,
    CAST(NULL AS STRING)                                           AS run_result_state,
    s.step_state                                                   AS task_result_state,

    BIGINT(unix_timestamp(s.ts_step_ended) - unix_timestamp(s.ts_step_started))
                                                                   AS total_duration_seconds,
    BIGINT(unix_timestamp(s.ts_step_ended) - unix_timestamp(s.ts_step_started))
                                                                   AS execution_duration_seconds,

    dch_health.p50_driver_cpu_busy_percent,
    dch_health.p95_driver_cpu_busy_percent,
    CAST(NULL AS DOUBLE)                                           AS p50_driver_cpu_wait_percent,
    CAST(NULL AS DOUBLE)                                           AS p95_driver_cpu_wait_percent,
    dch_health.p50_worker_cpu_busy_percent,
    dch_health.p95_worker_cpu_busy_percent,
    CAST(NULL AS DOUBLE)                                           AS p50_worker_cpu_wait_percent,
    CAST(NULL AS DOUBLE)                                           AS p95_worker_cpu_wait_percent,
    CAST(NULL AS DOUBLE)                                           AS p50_driver_mem_used_percent,
    CAST(NULL AS DOUBLE)                                           AS p95_driver_mem_used_percent,
    dch_health.p50_worker_mem_used_percent,
    dch_health.p95_worker_mem_used_percent,
    CAST(NULL AS DOUBLE)                                           AS local_disk_utilization_pct_p95,

    CAST(0 AS DECIMAL(25, 4))                                      AS total_dbu_consumed,
    CAST(0 AS DECIMAL(37, 4))                                      AS total_dbu_cost_usd,
    CAST(0 AS DECIMAL(37, 4))                                      AS total_dbu_list_cost_usd,
    CAST(NULL AS DOUBLE)                                           AS dbu_rate_usd,
    CAST(NULL AS STRING)                                           AS dbu_pricing_sku,
    CAST(ROUND(COALESCE(dch_pro.total_ec2_cost_usd, 0), 4) AS DECIMAL(38, 4))
                                                                   AS total_ec2_cost_usd,
    CAST(ROUND(COALESCE(dch_pro.total_ebs_cost_usd, 0), 4) AS DECIMAL(38, 4))
                                                                   AS total_ebs_cost_usd,
    CAST(ROUND(COALESCE(dch_pro.total_emr_fee_cost_usd, 0), 4) AS DECIMAL(38, 4))
                                                                   AS total_emr_fee_cost_usd,
    CAST(ROUND(COALESCE(dch_pro.ec2_spot_hours, 0), 4) AS DECIMAL(38, 4))
                                                                   AS ec2_spot_hours,
    CAST(ROUND(COALESCE(dch_pro.ec2_on_demand_hours, 0), 4) AS DECIMAL(38, 4))
                                                                   AS ec2_on_demand_hours,
    COALESCE(dch_pro.cost_source, 'missing')                       AS cost_source,
    CAST(
        ROUND(
            COALESCE(CAST(dch_pro.total_ec2_cost_usd AS DOUBLE), 0.0)
            + COALESCE(CAST(dch_pro.total_ebs_cost_usd AS DOUBLE), 0.0)
            + COALESCE(CAST(dch_pro.total_emr_fee_cost_usd AS DOUBLE), 0.0),
            4
        ) AS DECIMAL(38, 4)
    )                                                              AS total_cost_usd,
    CAST(ROUND(COALESCE(dch_pro.total_ec2_net_cost_usd, 0), 4) AS DECIMAL(38, 4))
                                                                   AS total_ec2_net_cost_usd,
    CAST(ROUND(COALESCE(dch_pro.total_ebs_net_cost_usd, 0), 4) AS DECIMAL(38, 4))
                                                                   AS total_ebs_net_cost_usd,
    CAST(ROUND(COALESCE(dch_pro.total_emr_fee_net_cost_usd, 0), 4) AS DECIMAL(38, 4))
                                                                   AS total_emr_fee_net_cost_usd,
    CAST(
        ROUND(
            COALESCE(CAST(dch_pro.total_ec2_net_cost_usd AS DOUBLE), 0.0)
            + COALESCE(CAST(dch_pro.total_ebs_net_cost_usd AS DOUBLE), 0.0)
            + COALESCE(CAST(dch_pro.total_emr_fee_net_cost_usd AS DOUBLE), 0.0),
            4
        ) AS DECIMAL(38, 4)
    )                                                              AS total_net_cost_usd,
    CAST(ROUND(COALESCE(dch_pro.total_discount_usd, 0), 4) AS DECIMAL(38, 4))
                                                                   AS total_discount_usd,

    CAST(FALSE AS BOOLEAN)                                         AS is_photon,
    CAST(FALSE AS BOOLEAN)                                         AS has_local_nvme,
    CAST(FALSE AS BOOLEAN)                                         AS is_pool_backed,
    CAST(FALSE AS BOOLEAN)                                         AS is_job_on_interactive,
    CAST(FALSE AS BOOLEAN)                                         AS dbu_negotiated_price_missing,

    s.step_state = 'COMPLETED'                                     AS is_success,
    s.step_state = 'FAILED'                                        AS is_failed,
    CAST(FALSE AS BOOLEAN)                                         AS is_pool_acquisition_slow,
    COALESCE(dch_pro.tag_sensitive_data = 'true', FALSE)           AS is_sensitive_data,
    CAST(FALSE AS BOOLEAN)                                         AS has_stage_data,
    CAST(FALSE AS BOOLEAN)                                         AS is_stage_attribution_ambiguous,

    CAST(NULL AS BIGINT)                                           AS stage_count,
    CAST(NULL AS BIGINT)                                           AS failed_stage_count,
    CAST(NULL AS BIGINT)                                           AS spark_app_count,
    CAST(NULL AS BIGINT)                                           AS total_executor_run_time_ms,
    CAST(NULL AS BIGINT)                                           AS total_executor_cpu_time_ms,
    CAST(NULL AS BIGINT)                                           AS total_disk_bytes_spilled,
    CAST(NULL AS BIGINT)                                           AS total_memory_bytes_spilled,
    CAST(NULL AS BIGINT)                                           AS max_peak_execution_memory_bytes,
    CAST(NULL AS BIGINT)                                           AS total_input_bytes_read,
    CAST(NULL AS BIGINT)                                           AS total_output_bytes_written,
    CAST(NULL AS BIGINT)                                           AS total_shuffle_bytes_read,
    CAST(NULL AS BIGINT)                                           AS total_shuffle_bytes_written,
    CAST(NULL AS BIGINT)                                           AS max_jvm_heap_bytes,
    CAST(NULL AS BIGINT)                                           AS total_gc_time_ms,
    CAST(NULL AS BIGINT)                                           AS max_task_run_time_ms,
    CAST(NULL AS DOUBLE)                                           AS max_task_skew_ratio,
    CAST(NULL AS STRING)                                           AS last_stage_failure_reason,

    CAST(NULL AS BIGINT)                                           AS setup_duration_seconds,
    CAST(NULL AS BIGINT)                                           AS pre_init_script_seconds,
    CAST(NULL AS BIGINT)                                           AS init_script_seconds,
    CAST(NULL AS BIGINT)                                           AS post_init_script_seconds,
    CAST(NULL AS BIGINT)                                           AS cluster_startup_seconds,

    s.dt_step_started,
    s.ts_step_started,
    s.ts_step_ended,
    s.ts_cluster_started                                             AS ts_run_started,
    s.ts_cluster_ended                                               AS ts_run_ended,
    CURRENT_TIMESTAMP()                                              AS ts_load,

    YEAR(s.dt_step_started)                                          AS year,
    MONTH(s.dt_step_started)                                         AS month,
    DAY(s.dt_step_started)                                           AS day

FROM
    step_with_seconds AS s
LEFT JOIN
    step_dch_prorated AS dch_pro
        ON  dch_pro.airflow_dag_id  = s.airflow_dag_id
        AND dch_pro.airflow_run_id  = s.airflow_run_id
        AND dch_pro.airflow_task_id = s.airflow_task_id
        AND dch_pro.id_emr_cluster  = s.id_emr_cluster
        AND dch_pro.id_emr_step     = s.id_emr_step
LEFT JOIN
    step_dch_health AS dch_health
        ON  dch_health.airflow_dag_id  = s.airflow_dag_id
        AND dch_health.airflow_run_id  = s.airflow_run_id
        AND dch_health.airflow_task_id = s.airflow_task_id
        AND dch_health.id_emr_cluster  = s.id_emr_cluster
        AND dch_health.id_emr_step     = s.id_emr_step
),

cohort_matches AS (
    SELECT
        f.sk_emr_task_run,
        r.cost_cohort,
        r.priority
    FROM
        final AS f
    INNER JOIN
        datalake_databricks_pricing.dim_cost_cohort AS r
            ON f.team_owner = r.match_value
    WHERE
        r.rule_type = 'team_owner_exact'

    UNION ALL

    SELECT
        f.sk_emr_task_run,
        r.cost_cohort,
        r.priority
    FROM
        final AS f
    INNER JOIN
        datalake_databricks_pricing.dim_cost_cohort AS r
            ON f.provisioner = r.match_value
    WHERE
        r.rule_type = 'provisioner_exact'

    UNION ALL

    SELECT
        f.sk_emr_task_run,
        r.cost_cohort,
        r.priority
    FROM
        final AS f
    CROSS JOIN
        datalake_databricks_pricing.dim_cost_cohort AS r
    WHERE
        r.rule_type = 'team_owner_prefix'
        AND f.team_owner LIKE CONCAT(r.match_value, '%')

    UNION ALL

    SELECT
        f.sk_emr_task_run,
        r.cost_cohort,
        r.priority
    FROM
        final AS f
    CROSS JOIN
        datalake_databricks_pricing.dim_cost_cohort AS r
    WHERE
        r.rule_type = 'workload_prefix'
        AND LOWER(f.airflow_dag_id) LIKE CONCAT(r.match_value, '%')

    UNION ALL

    SELECT
        f.sk_emr_task_run,
        r.cost_cohort,
        r.priority
    FROM
        final AS f
    CROSS JOIN
        datalake_databricks_pricing.dim_cost_cohort AS r
    WHERE
        r.rule_type = 'workload_like'
        AND LOWER(f.airflow_dag_id) LIKE r.match_value
),
cohort_match AS (
    SELECT
        sk_emr_task_run,
        MIN_BY(cost_cohort, priority)                      AS cost_cohort
    FROM
        cohort_matches
    GROUP BY
        sk_emr_task_run
)

SELECT
    f.sk_emr_task_run,
    f.sk_emr_cluster,
    f.sk_emr_run,
    f.sk_step_started_date,
    f.id_emr_cluster,
    f.id_emr_step,
    f.airflow_dag_id,
    f.airflow_run_id,
    f.airflow_task_id,
    f.team_owner,
    f.cost_center,
    f.ecosystem,
    f.environment,
    f.data_classification,
    f.provisioner,
    COALESCE(cm.cost_cohort, 'other')                              AS cost_cohort,
    f.cluster_name,
    f.cluster_source,
    f.driver_node_type,
    f.worker_node_type,
    f.dbr_version,
    f.worker_count,
    f.min_autoscale_workers,
    f.max_autoscale_workers,
    f.peak_concurrent_workers,
    f.run_type,
    f.run_result_state,
    f.task_result_state,
    f.total_duration_seconds,
    f.execution_duration_seconds,
    f.p50_driver_cpu_busy_percent,
    f.p95_driver_cpu_busy_percent,
    f.p50_driver_cpu_wait_percent,
    f.p95_driver_cpu_wait_percent,
    f.p50_worker_cpu_busy_percent,
    f.p95_worker_cpu_busy_percent,
    f.p50_worker_cpu_wait_percent,
    f.p95_worker_cpu_wait_percent,
    f.p50_driver_mem_used_percent,
    f.p95_driver_mem_used_percent,
    f.p50_worker_mem_used_percent,
    f.p95_worker_mem_used_percent,
    f.local_disk_utilization_pct_p95,
    f.total_dbu_consumed,
    f.total_dbu_cost_usd,
    f.total_dbu_list_cost_usd,
    f.dbu_rate_usd,
    f.dbu_pricing_sku,
    f.total_ec2_cost_usd,
    f.total_ebs_cost_usd,
    f.total_emr_fee_cost_usd,
    f.ec2_spot_hours,
    f.ec2_on_demand_hours,
    f.cost_source,
    f.total_cost_usd,
    f.total_ec2_net_cost_usd,
    f.total_ebs_net_cost_usd,
    f.total_emr_fee_net_cost_usd,
    f.total_net_cost_usd,
    f.total_discount_usd,
    f.is_photon,
    f.has_local_nvme,
    f.is_pool_backed,
    f.is_job_on_interactive,
    f.dbu_negotiated_price_missing,
    f.is_success,
    f.is_failed,
    f.is_pool_acquisition_slow,
    f.is_sensitive_data,
    f.has_stage_data,
    f.is_stage_attribution_ambiguous,
    f.stage_count,
    f.failed_stage_count,
    f.spark_app_count,
    f.total_executor_run_time_ms,
    f.total_executor_cpu_time_ms,
    f.total_disk_bytes_spilled,
    f.total_memory_bytes_spilled,
    f.max_peak_execution_memory_bytes,
    f.total_input_bytes_read,
    f.total_output_bytes_written,
    f.total_shuffle_bytes_read,
    f.total_shuffle_bytes_written,
    f.max_jvm_heap_bytes,
    f.total_gc_time_ms,
    f.max_task_run_time_ms,
    f.max_task_skew_ratio,
    f.last_stage_failure_reason,
    f.setup_duration_seconds,
    f.pre_init_script_seconds,
    f.init_script_seconds,
    f.post_init_script_seconds,
    f.cluster_startup_seconds,
    f.dt_step_started                                              AS dt_task_started,
    f.ts_step_started                                              AS ts_task_started,
    f.ts_step_ended                                                AS ts_task_ended,
    f.ts_run_started,
    f.ts_run_ended,
    f.ts_load,
    f.year,
    f.month,
    f.day
FROM
    final f
LEFT JOIN
    cohort_match cm
        ON cm.sk_emr_task_run = f.sk_emr_task_run
