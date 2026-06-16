-- ============================================================================
-- enrich_rightsizing_outcomes.sql
--
-- Prod vs __validation twin comparison for cluster right-sizing feedback.
-- Grain: one row per validation Airflow dag run (validation_airflow_run_id).
--
-- Reference prod pairing ladder: (1) reference_prod_dag_run_id persisted in the
-- validation run's conf by trigger_cluster_validation_dags.py, (2) candidate
-- whose derived load window equals the validation's own conf window, (3)
-- fastest successful prod run in 14d with wall >= 480s. Conf is a pickled dict
-- stored as bytea-hex text; fields are extracted via unhex+regexp.
--
-- Promotion thresholds align with scripts/promote_rightsizing_validations.py:
-- REGRESSION_TOLERANCE_PCT = 5.0, STRONG_POSITIVE_COST_PCT = -15.0, MEM_WARN = 82
-- is_decisive_validation_run mirrors decisive_row_for_dag() newest-first scan.
-- outcome/promotion_action CASE order matches decide_promotion_action(): runtime
-- fail, incomplete pairing (extend), cost, wall, mem warn, pass/promote.
-- ============================================================================
WITH validation_runs_raw AS (
    SELECT
        id_dag                                                                       AS validation_airflow_dag_id,
        id_run                                                                       AS validation_airflow_run_id,
        REGEXP_REPLACE(id_dag, '__validation$', '')                                  AS prod_airflow_dag_id,
        ts_started                                                                   AS val_ts_started,
        ts_ended                                                                     AS val_ts_ended,
        DATE(ts_started)                                                             AS val_dt,
        state                                                                        AS val_state,
        CASE
            WHEN configuration IS NOT NULL AND SUBSTRING(configuration, 1, 2) = '\\x'
                THEN DECODE(UNHEX(SUBSTRING(configuration, 3)), 'ISO-8859-1')
        END                                                                          AS conf_text,
        ROW_NUMBER() OVER (
            PARTITION BY id_dag, id_run
            ORDER BY ts_updated DESC
        )                                                                            AS dedup_rn
    FROM datalake_astro_clean.dag_run
    WHERE MAKE_DATE(year, month, day) >= DATE('{load_start_date}')
      AND ts_started >= TO_TIMESTAMP('{load_start_date}')
      AND ts_started < TO_TIMESTAMP('{load_end_date}') + INTERVAL 1 DAY
      AND id_dag LIKE 'bietlejuice.%'
      AND REGEXP_LIKE(id_dag, '__validation$')
      AND state IN ('success', 'failed')
      AND run_type = 'manual'
),
validation_runs AS (
    SELECT
        validation_airflow_dag_id,
        validation_airflow_run_id,
        prod_airflow_dag_id,
        val_ts_started,
        val_ts_ended,
        val_dt,
        val_state,
        TO_DATE(NULLIF(
            regexp_extract(conf_text, 'load_start_date.{{1,5}}?(\\d{{4}}-\\d{{2}}-\\d{{2}})', 1), ''
        ))                                                                           AS val_conf_load_start_date,
        TO_DATE(NULLIF(
            regexp_extract(conf_text, 'load_end_date.{{1,5}}?(\\d{{4}}-\\d{{2}}-\\d{{2}})', 1), ''
        ))                                                                           AS val_conf_load_end_date,
        NULLIF(
            regexp_extract(
                conf_text,
                'reference_prod_dag_run_id.{{1,5}}?((?:manual|scheduled|dataset_triggered|backfill)__[0-9T:.+-]+)',
                1
            ), ''
        )                                                                            AS conf_reference_prod_run_id
    FROM validation_runs_raw
    WHERE dedup_rn = 1
),
prod_astro AS (
    SELECT
        prod_airflow_dag_id,
        prod_airflow_run_id,
        ts_started,
        ts_ended,
        ts_data_interval_started,
        ts_data_interval_ended,
        TO_DATE(NULLIF(
            regexp_extract(conf_text, 'load_start_date.{{1,5}}?(\\d{{4}}-\\d{{2}}-\\d{{2}})', 1), ''
        ))                                                                           AS prod_conf_load_start_date,
        TO_DATE(NULLIF(
            regexp_extract(conf_text, 'load_end_date.{{1,5}}?(\\d{{4}}-\\d{{2}}-\\d{{2}})', 1), ''
        ))                                                                           AS prod_conf_load_end_date
    FROM (
        SELECT
            id_dag                                                                   AS prod_airflow_dag_id,
            id_run                                                                   AS prod_airflow_run_id,
            ts_started,
            ts_ended,
            ts_data_interval_started,
            ts_data_interval_ended,
            CASE
                WHEN configuration IS NOT NULL AND SUBSTRING(configuration, 1, 2) = '\\x'
                    THEN DECODE(UNHEX(SUBSTRING(configuration, 3)), 'ISO-8859-1')
            END                                                                      AS conf_text,
            ROW_NUMBER() OVER (
                PARTITION BY id_dag, id_run
                ORDER BY ts_updated DESC
            )                                                                        AS dedup_rn
        FROM datalake_astro_clean.dag_run
        WHERE MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 16)
          AND id_dag LIKE 'bietlejuice.%'
          AND NOT REGEXP_LIKE(id_dag, '__validation$')
          AND state = 'success'
          AND ts_ended IS NOT NULL
          AND ts_started IS NOT NULL
    )
    WHERE dedup_rn = 1
),
reference_prod_candidates AS (
    SELECT
        v.validation_airflow_dag_id,
        v.validation_airflow_run_id,
        v.prod_airflow_dag_id,
        v.val_ts_started,
        v.val_ts_ended,
        v.val_dt,
        v.val_state,
        v.val_conf_load_start_date,
        v.val_conf_load_end_date,
        v.conf_reference_prod_run_id,
        p.prod_airflow_run_id                                                        AS reference_prod_airflow_run_id,
        p.ts_started                                                                 AS ref_ts_started,
        p.ts_ended                                                                   AS ref_ts_ended,
        COALESCE(p.prod_airflow_run_id = v.conf_reference_prod_run_id, FALSE)        AS is_conf_run_id_match,
        (p.prod_conf_load_start_date IS NOT NULL
         AND p.prod_conf_load_end_date IS NOT NULL)                                  AS is_ref_window_from_conf,
        COALESCE(p.prod_conf_load_start_date, DATE(p.ts_data_interval_started))      AS ref_derived_start,
        COALESCE(
            p.prod_conf_load_end_date,
            DATE_SUB(DATE(p.ts_data_interval_ended), 1)
        )                                                                            AS ref_derived_end_raw,
        UNIX_TIMESTAMP(p.ts_ended) - UNIX_TIMESTAMP(p.ts_started)                    AS ref_duration_seconds
    FROM validation_runs AS v
    LEFT JOIN prod_astro AS p
        ON v.prod_airflow_dag_id = p.prod_airflow_dag_id
       AND (
            p.prod_airflow_run_id = v.conf_reference_prod_run_id
            OR (
                p.ts_ended <= v.val_ts_started
                AND p.ts_ended >= v.val_ts_started - INTERVAL 14 DAYS
                AND UNIX_TIMESTAMP(p.ts_ended) - UNIX_TIMESTAMP(p.ts_started) >= 480
            )
       )
),
reference_prod_ranked AS (
    SELECT
        c.*,
        CASE
            WHEN c.ref_derived_start IS NOT NULL
             AND c.ref_derived_end_raw IS NOT NULL
             AND c.ref_derived_start >= c.ref_derived_end_raw
                THEN DATE_ADD(c.ref_derived_end_raw, 1)
            ELSE c.ref_derived_end_raw
        END                                                                          AS ref_derived_end_final,
        COALESCE(
            c.val_conf_load_start_date IS NOT NULL
            AND c.val_conf_load_end_date IS NOT NULL
            AND c.val_conf_load_start_date = c.ref_derived_start
            AND c.val_conf_load_end_date IN (
                c.ref_derived_end_raw,
                CASE
                    WHEN c.ref_derived_start >= c.ref_derived_end_raw
                        THEN DATE_ADD(c.ref_derived_end_raw, 1)
                    ELSE c.ref_derived_end_raw
                END
            ),
            FALSE
        )                                                                            AS is_window_match,
        ROW_NUMBER() OVER (
            PARTITION BY c.validation_airflow_run_id
            ORDER BY
                CASE WHEN c.is_conf_run_id_match THEN 0 ELSE 1 END,
                CASE
                    WHEN c.val_conf_load_start_date IS NOT NULL
                     AND c.val_conf_load_start_date = c.ref_derived_start
                     AND c.val_conf_load_end_date IN (
                         c.ref_derived_end_raw,
                         CASE
                             WHEN c.ref_derived_start >= c.ref_derived_end_raw
                                 THEN DATE_ADD(c.ref_derived_end_raw, 1)
                             ELSE c.ref_derived_end_raw
                         END
                     )
                        THEN 0
                    ELSE 1
                END,
                c.ref_duration_seconds ASC,
                c.ref_ts_started DESC
        )                                                                            AS ref_rank
    FROM reference_prod_candidates AS c
),
validation_with_reference AS (
    SELECT
        r.validation_airflow_dag_id,
        r.validation_airflow_run_id,
        r.prod_airflow_dag_id,
        r.val_ts_started,
        r.val_ts_ended,
        r.val_dt,
        r.val_state,
        r.val_conf_load_start_date,
        r.val_conf_load_end_date,
        r.reference_prod_airflow_run_id,
        r.ref_ts_started,
        r.ref_ts_ended,
        r.ref_derived_start                                                          AS reference_load_start_date,
        r.ref_derived_end_final                                                      AS reference_load_end_date,
        CASE
            WHEN r.reference_prod_airflow_run_id IS NULL THEN NULL
            WHEN r.is_ref_window_from_conf THEN 'conf'
            ELSE 'data_interval'
        END                                                                          AS window_source,
        CASE
            WHEN r.reference_prod_airflow_run_id IS NULL THEN NULL
            WHEN r.is_conf_run_id_match THEN 'conf_run_id'
            WHEN r.is_window_match THEN 'conf_window'
            ELSE 'heuristic'
        END                                                                          AS reference_match_source
    FROM reference_prod_ranked AS r
    WHERE r.ref_rank = 1
),
fd_runs AS (
    SELECT
        airflow_dag_id,
        dt_dag_run_started,
        ts_logical_run_started,
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
    WHERE dt_dag_run_started >= DATE_SUB(DATE('{load_start_date}'), 16)
      AND dt_dag_run_started <= DATE('{load_end_date}')
      AND airflow_dag_id LIKE 'bietlejuice.%'
      AND is_job_on_interactive = FALSE
      AND COALESCE(total_cost_usd, 0) > 0
),
val_fd_ranked AS (
    SELECT
        v.validation_airflow_run_id,
        fd.total_cost_usd,
        fd.total_wall_clock_seconds,
        fd.drv_cpu_p50,
        fd.drv_cpu_p95,
        fd.drv_mem_p95,
        fd.wrk_cpu_p50,
        fd.wrk_cpu_p95,
        fd.wrk_mem_p95,
        fd.peak_concurrent_workers,
        fd.is_any_task_failed,
        fd.is_any_databricks_run_failed,
        fd.driver_node_type,
        fd.worker_node_type,
        fd.worker_count,
        fd.primary_dbr_version,
        ROW_NUMBER() OVER (
            PARTITION BY v.validation_airflow_run_id
            ORDER BY
                ABS(
                    UNIX_TIMESTAMP(fd.ts_logical_run_started)
                    - UNIX_TIMESTAMP(v.val_ts_started)
                ),
                fd.total_cost_usd DESC
        )                                                                            AS fd_rank
    FROM validation_with_reference AS v
    LEFT JOIN fd_runs AS fd
        ON fd.airflow_dag_id = v.validation_airflow_dag_id
       AND fd.ts_logical_run_started >= v.val_ts_started - INTERVAL 5 MINUTES
       AND fd.ts_logical_run_started <= COALESCE(v.val_ts_ended, v.val_ts_started)
            + INTERVAL 30 MINUTES
),
val_fd AS (
    SELECT *
    FROM val_fd_ranked
    WHERE fd_rank = 1
),
ref_fd_ranked AS (
    SELECT
        v.validation_airflow_run_id,
        fd.total_cost_usd,
        fd.total_wall_clock_seconds,
        fd.drv_cpu_p50,
        fd.drv_cpu_p95,
        fd.drv_mem_p95,
        fd.wrk_cpu_p50,
        fd.wrk_cpu_p95,
        fd.wrk_mem_p95,
        fd.peak_concurrent_workers,
        fd.is_any_task_failed,
        fd.is_any_databricks_run_failed,
        fd.driver_node_type,
        fd.worker_node_type,
        fd.worker_count,
        fd.primary_dbr_version,
        ROW_NUMBER() OVER (
            PARTITION BY v.validation_airflow_run_id
            ORDER BY
                ABS(
                    UNIX_TIMESTAMP(fd.ts_logical_run_started)
                    - UNIX_TIMESTAMP(v.ref_ts_started)
                ),
                fd.total_cost_usd DESC
        )                                                                            AS fd_rank
    FROM validation_with_reference AS v
    INNER JOIN fd_runs AS fd
        ON v.reference_prod_airflow_run_id IS NOT NULL
       AND fd.airflow_dag_id = v.prod_airflow_dag_id
       AND fd.ts_logical_run_started >= v.ref_ts_started - INTERVAL 5 MINUTES
       AND fd.ts_logical_run_started <= COALESCE(v.ref_ts_ended, v.ref_ts_started)
            + INTERVAL 5 MINUTES
       AND fd.total_wall_clock_seconds >= 300
),
ref_fd AS (
    SELECT *
    FROM ref_fd_ranked
    WHERE fd_rank = 1
),
dag_cadence AS (
    SELECT
        CASE
            WHEN REGEXP_LIKE(airflow_dag_id, '__validation$')
                THEN REGEXP_REPLACE(airflow_dag_id, '__validation$', '')
            ELSE airflow_dag_id
        END                                                                          AS prod_airflow_dag_id,
        ROUND(1440.0 * COUNT(DISTINCT dt_dag_run_started) / NULLIF(COUNT(*), 0), 1) AS schedule_interval_minutes
    FROM fd_runs
    WHERE NOT REGEXP_LIKE(airflow_dag_id, '__validation$')
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
    GROUP BY 1
),
paired AS (
    SELECT
        v.validation_airflow_run_id,
        v.validation_airflow_dag_id,
        v.prod_airflow_dag_id,
        v.val_ts_started,
        v.val_ts_ended,
        v.val_dt,
        v.val_conf_load_start_date,
        v.val_conf_load_end_date,
        v.reference_prod_airflow_run_id,
        v.ref_ts_started,
        v.ref_ts_ended,
        v.reference_load_start_date,
        v.reference_load_end_date,
        v.window_source,
        v.reference_match_source,
        CASE WHEN v.reference_prod_airflow_run_id IS NOT NULL THEN 1 ELSE 0 END      AS prod_run_count,
        1                                                                            AS val_run_count,
        CASE
            WHEN ref_fd.is_any_task_failed OR ref_fd.is_any_databricks_run_failed
                THEN 1
            ELSE 0
        END                                                                          AS prod_failure_count,
        CASE
            WHEN val_fd.is_any_task_failed
              OR val_fd.is_any_databricks_run_failed
              OR v.val_state = 'failed'
                THEN 1
            ELSE 0
        END                                                                          AS val_failure_count,
        CASE
            WHEN val_fd.validation_airflow_run_id IS NOT NULL
             AND COALESCE(val_fd.is_any_task_failed, FALSE) = FALSE
             AND COALESCE(val_fd.is_any_databricks_run_failed, FALSE) = FALSE
             AND v.val_state = 'success'
                THEN 1
            ELSE 0
        END                                                                          AS val_clean_run_count,
        ROUND(ref_fd.total_cost_usd, 6)                                              AS prod_avg_cost_usd,
        ROUND(val_fd.total_cost_usd, 6)                                              AS val_avg_cost_usd,
        ROUND(ref_fd.total_wall_clock_seconds / 60.0, 1)                             AS prod_wall_p50_min,
        ROUND(ref_fd.total_wall_clock_seconds / 60.0, 1)                             AS prod_wall_p95_min,
        ROUND(val_fd.total_wall_clock_seconds / 60.0, 1)                             AS val_wall_p50_min,
        ROUND(val_fd.total_wall_clock_seconds / 60.0, 1)                             AS val_wall_p95_min,
        ROUND(ref_fd.drv_cpu_p50, 1)                                                 AS prod_drv_cpu_p50,
        ROUND(ref_fd.drv_cpu_p95, 1)                                                 AS prod_drv_cpu_p95,
        ROUND(ref_fd.drv_mem_p95, 1)                                                 AS prod_drv_mem_p95,
        ROUND(ref_fd.wrk_cpu_p50, 1)                                                 AS prod_wrk_cpu_p50,
        ROUND(ref_fd.wrk_cpu_p95, 1)                                                 AS prod_wrk_cpu_p95,
        ROUND(ref_fd.wrk_mem_p95, 1)                                                 AS prod_wrk_mem_p95,
        ROUND(val_fd.drv_cpu_p50, 1)                                                 AS val_drv_cpu_p50,
        ROUND(val_fd.drv_cpu_p95, 1)                                                 AS val_drv_cpu_p95,
        ROUND(val_fd.drv_mem_p95, 1)                                                 AS val_drv_mem_p95,
        ROUND(val_fd.wrk_cpu_p50, 1)                                                 AS val_wrk_cpu_p50,
        ROUND(val_fd.wrk_cpu_p95, 1)                                                 AS val_wrk_cpu_p95,
        ROUND(val_fd.wrk_mem_p95, 1)                                                 AS val_wrk_mem_p95,
        ref_fd.peak_concurrent_workers                                               AS prod_peak_concurrent_workers,
        val_fd.peak_concurrent_workers                                               AS val_peak_concurrent_workers,
        ref_fd.driver_node_type                                                      AS prod_driver_node_type,
        ref_fd.worker_node_type                                                      AS prod_worker_node_type,
        ref_fd.worker_count                                                          AS prod_worker_count,
        ref_fd.primary_dbr_version                                                   AS prod_dbr_version,
        val_fd.driver_node_type                                                      AS val_driver_node_type,
        val_fd.worker_node_type                                                      AS val_worker_node_type,
        val_fd.worker_count                                                          AS val_worker_count,
        val_fd.primary_dbr_version                                                   AS val_dbr_version
    FROM validation_with_reference AS v
    LEFT JOIN val_fd
        ON v.validation_airflow_run_id = val_fd.validation_airflow_run_id
    LEFT JOIN ref_fd
        ON v.validation_airflow_run_id = ref_fd.validation_airflow_run_id
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
            AND p.prod_avg_cost_usd > 0
            AND (p.val_avg_cost_usd - p.prod_avg_cost_usd) / p.prod_avg_cost_usd * 100.0 <= 5.0
            AND (
                (
                    COALESCE(c.schedule_interval_minutes, 1440.0) > 120
                    AND p.val_wall_p50_min IS NOT NULL
                    AND p.prod_wall_p50_min IS NOT NULL
                    AND p.val_wall_p50_min <= p.prod_wall_p50_min * 1.05
                )
                OR (
                    COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
                    AND p.val_wall_p95_min IS NOT NULL
                    AND p.prod_wall_p95_min IS NOT NULL
                    AND p.val_wall_p95_min <= GREATEST(
                        0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                        p.prod_wall_p95_min * 1.05
                    )
                )
            )
        )                                                                            AS is_promote_eligible,
        CASE
            WHEN p.val_failure_count > 0 THEN 'fail'
            WHEN p.val_clean_run_count < 1 THEN 'extend'
            WHEN p.val_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd > 0
             AND (p.val_avg_cost_usd - p.prod_avg_cost_usd) / p.prod_avg_cost_usd * 100.0 > 5.0
                THEN 'fail'
            WHEN COALESCE(c.schedule_interval_minutes, 1440.0) > 120
             AND p.val_wall_p50_min IS NOT NULL
             AND p.prod_wall_p50_min IS NOT NULL
             AND p.val_wall_p50_min > p.prod_wall_p50_min * 1.05 THEN 'fail'
            WHEN COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
             AND p.val_wall_p95_min IS NOT NULL
             AND p.prod_wall_p95_min IS NOT NULL
             AND p.val_wall_p95_min > GREATEST(
                0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                p.prod_wall_p95_min * 1.05
             ) THEN 'fail'
            WHEN GREATEST(COALESCE(p.val_drv_mem_p95, 0), COALESCE(p.val_wrk_mem_p95, 0)) > 82
                THEN 'warn'
            WHEN p.val_clean_run_count >= 1
             AND p.val_failure_count = 0
             AND p.val_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd > 0
             AND (p.val_avg_cost_usd - p.prod_avg_cost_usd) / p.prod_avg_cost_usd * 100.0 <= 5.0
             AND (
                (
                    COALESCE(c.schedule_interval_minutes, 1440.0) > 120
                    AND p.val_wall_p50_min IS NOT NULL
                    AND p.prod_wall_p50_min IS NOT NULL
                    AND p.val_wall_p50_min <= p.prod_wall_p50_min * 1.05
                )
                OR (
                    COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
                    AND p.val_wall_p95_min IS NOT NULL
                    AND p.prod_wall_p95_min IS NOT NULL
                    AND p.val_wall_p95_min <= GREATEST(
                        0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                        p.prod_wall_p95_min * 1.05
                    )
                )
             ) THEN 'pass'
            ELSE 'extend'
        END                                                                          AS outcome,
        CASE
            WHEN p.val_failure_count > 0 THEN 'reject'
            WHEN p.val_clean_run_count < 1 THEN 'extend'
            WHEN p.val_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd > 0
             AND (p.val_avg_cost_usd - p.prod_avg_cost_usd) / p.prod_avg_cost_usd * 100.0 > 5.0
                THEN 'reject'
            WHEN COALESCE(c.schedule_interval_minutes, 1440.0) > 120
             AND p.val_wall_p50_min IS NOT NULL
             AND p.prod_wall_p50_min IS NOT NULL
             AND p.val_wall_p50_min > p.prod_wall_p50_min * 1.05 THEN 'reject'
            WHEN COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
             AND p.val_wall_p95_min IS NOT NULL
             AND p.prod_wall_p95_min IS NOT NULL
             AND p.val_wall_p95_min > GREATEST(
                0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                p.prod_wall_p95_min * 1.05
             ) THEN 'reject'
            WHEN GREATEST(COALESCE(p.val_drv_mem_p95, 0), COALESCE(p.val_wrk_mem_p95, 0)) > 82
                THEN 'extend'
            WHEN p.val_clean_run_count >= 1
             AND p.val_failure_count = 0
             AND p.val_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd IS NOT NULL
             AND p.prod_avg_cost_usd > 0
             AND (p.val_avg_cost_usd - p.prod_avg_cost_usd) / p.prod_avg_cost_usd * 100.0 <= 5.0
             AND (
                (
                    COALESCE(c.schedule_interval_minutes, 1440.0) > 120
                    AND p.val_wall_p50_min IS NOT NULL
                    AND p.prod_wall_p50_min IS NOT NULL
                    AND p.val_wall_p50_min <= p.prod_wall_p50_min * 1.05
                )
                OR (
                    COALESCE(c.schedule_interval_minutes, 1440.0) <= 120
                    AND p.val_wall_p95_min IS NOT NULL
                    AND p.prod_wall_p95_min IS NOT NULL
                    AND p.val_wall_p95_min <= GREATEST(
                        0.8 * COALESCE(c.schedule_interval_minutes, 60.0),
                        p.prod_wall_p95_min * 1.05
                    )
                )
             ) THEN 'promote'
            ELSE 'extend'
        END                                                                          AS promotion_action
    FROM paired AS p
    LEFT JOIN dag_cadence AS c
        ON p.prod_airflow_dag_id = c.prod_airflow_dag_id
),
with_signals AS (
    SELECT
        s.*,
        (
            s.val_failure_count = 0
            AND (
                (s.delta_cost_pct IS NOT NULL AND s.delta_cost_pct <= -15.0)
                OR (
                    s.delta_cost_pct IS NOT NULL
                    AND s.delta_cost_pct <= 5.0
                    AND (
                        (
                            COALESCE(s.schedule_interval_minutes, 1440.0) > 120
                            AND s.val_wall_p50_min IS NOT NULL
                            AND s.prod_wall_p50_min IS NOT NULL
                            AND s.val_wall_p50_min <= s.prod_wall_p50_min * 1.05
                        )
                        OR (
                            COALESCE(s.schedule_interval_minutes, 1440.0) <= 120
                            AND s.val_wall_p95_min IS NOT NULL
                            AND s.prod_wall_p95_min IS NOT NULL
                            AND s.val_wall_p95_min <= GREATEST(
                                0.8 * COALESCE(s.schedule_interval_minutes, 60.0),
                                s.prod_wall_p95_min * 1.05
                            )
                        )
                    )
                )
            )
        )                                                                            AS has_strong_positive_signal
    FROM scored AS s
),
windowed AS (
    SELECT
        w.*,
        ROW_NUMBER() OVER (
            PARTITION BY w.prod_airflow_dag_id
            ORDER BY w.val_ts_started ASC
        )                                                                            AS validation_attempt_number,
        ROW_NUMBER() OVER (
            PARTITION BY w.prod_airflow_dag_id
            ORDER BY w.val_ts_started DESC
        ) = 1                                                                        AS is_latest_validation_run,
        LAG(w.outcome) OVER (
            PARTITION BY w.prod_airflow_dag_id
            ORDER BY w.val_ts_started
        )                                                                            AS prior_outcome,
        LAG(w.val_failure_count) OVER (
            PARTITION BY w.prod_airflow_dag_id
            ORDER BY w.val_ts_started
        )                                                                            AS prior_val_failure_count,
        ROW_NUMBER() OVER (
            PARTITION BY w.prod_airflow_dag_id
            ORDER BY
                CASE
                    WHEN w.promotion_action IN ('promote', 'reject')
                      OR w.outcome = 'warn' THEN 0
                    WHEN w.has_strong_positive_signal THEN 1
                    ELSE 2
                END,
                w.val_ts_started DESC
        ) = 1                                                                        AS is_decisive_validation_run,
        (
            (
                LAG(w.outcome) OVER (
                    PARTITION BY w.prod_airflow_dag_id ORDER BY w.val_ts_started
                ) = 'fail'
                AND w.outcome IN ('pass', 'warn')
            )
            OR (
                LAG(w.val_failure_count) OVER (
                    PARTITION BY w.prod_airflow_dag_id ORDER BY w.val_ts_started
                ) = 1
                AND w.val_failure_count = 0
                AND (
                    (
                        w.val_avg_cost_usd IS NOT NULL
                        AND LAG(w.val_avg_cost_usd) OVER (
                            PARTITION BY w.prod_airflow_dag_id ORDER BY w.val_ts_started
                        ) IS NOT NULL
                        AND w.val_avg_cost_usd < LAG(w.val_avg_cost_usd) OVER (
                            PARTITION BY w.prod_airflow_dag_id ORDER BY w.val_ts_started
                        )
                    )
                    OR (
                        w.val_wall_p50_min IS NOT NULL
                        AND LAG(w.val_wall_p50_min) OVER (
                            PARTITION BY w.prod_airflow_dag_id ORDER BY w.val_ts_started
                        ) IS NOT NULL
                        AND w.val_wall_p50_min < LAG(w.val_wall_p50_min) OVER (
                            PARTITION BY w.prod_airflow_dag_id ORDER BY w.val_ts_started
                        )
                    )
                )
            )
        )                                                                            AS is_improved_vs_prior_attempt
    FROM with_signals AS w
)
SELECT
    prod_airflow_dag_id,
    validation_airflow_run_id,
    validation_airflow_dag_id,
    val_ts_started,
    val_ts_ended,
    val_dt,
    reference_prod_airflow_run_id,
    ref_ts_started,
    ref_ts_ended,
    reference_load_start_date,
    reference_load_end_date,
    window_source,
    reference_match_source,
    val_conf_load_start_date,
    val_conf_load_end_date,
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
    validation_attempt_number,
    is_latest_validation_run,
    is_decisive_validation_run,
    prior_outcome,
    prior_val_failure_count,
    is_improved_vs_prior_attempt,
    has_strong_positive_signal,
    CURRENT_TIMESTAMP()                                                            AS ts_load
FROM windowed
