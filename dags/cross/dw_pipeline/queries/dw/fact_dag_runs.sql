SELECT
    dr.id_dag_run AS sk_dag_run,
    COALESCE(dr.id_dag, -1) AS sk_dag,
    COALESCE(dr.id_run, -1) AS sk_run,
    COALESCE(d.id_line, -1) AS sk_line,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_run, 'yyyyMMdd')), -1) AS sk_run_date,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_started, 'yyyyMMdd')), -1) AS sk_started_date,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_started_brt, 'yyyyMMdd')), -1) AS sk_started_brt_date,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_ended, 'yyyyMMdd')), -1) AS sk_ended_date,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_ended_brt, 'yyyyMMdd')), -1) AS sk_ended_brt_date,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_first_execution_success, 'yyyyMMdd')), -1) AS sk_first_execution_success_date,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_first_execution_success_brt, 'yyyyMMdd')), -1) AS sk_first_execution_success_brt_date,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_last_composer_run, 'yyyyMMdd')), -1) AS sk_last_composer_run_date,
    COALESCE(BIGINT(DATE_FORMAT(dr.ts_last_composer_run_brt, 'yyyyMMdd')), -1) AS sk_last_composer_run_brt_date,
    dr.state,
    dr.duration,
    dr.had_external_trigger,
    dr.is_triggered_by_mediator,
    dr.is_manual_run,
    dr.is_first_run_ever,
    dr.is_run_successful,
    dr.is_in_exclusion_list,
    dr.is_first_execution_inside_sla,
    dr.has_been_cleared,
    DATE(dr.ts_run) AS dt_run,
    dr.ts_started,
    dr.ts_started_brt,
    dr.ts_ended,
    dr.ts_ended_brt,
    dr.ts_first_execution_success,
    dr.ts_first_execution_success_brt,
    dr.ts_last_composer_run,
    dr.ts_last_composer_run_brt,
    NOW() AS ts_load
FROM
    datalake_pipeline.dag_run AS dr
JOIN
    datalake_pipeline.dag AS d
        ON dr.id_dag = d.id_dag