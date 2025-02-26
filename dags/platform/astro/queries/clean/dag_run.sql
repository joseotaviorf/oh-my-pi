SELECT
    id,
    dag_id,
    run_id AS id_run,
    log_template_id AS id_log_template,
    creating_job_id AS id_creating_job,
    state,
    run_type,
    conf AS configuration,
    dag_hash,
    clear_number,
    external_trigger AS had_external_trigger,
    last_scheduling_decision::TIMESTAMP AS ts_last_scheduling_decision,
    data_interval_start::TIMESTAMP AS ts_data_interval_started,
    data_interval_end::TIMESTAMP AS ts_data_interval_ended,
    updated_at::TIMESTAMP AS ts_updated,
    execution_date::TIMESTAMP AS ts_executed,
    queued_at::TIMESTAMP AS ts_queued,
    start_date::TIMESTAMP AS ts_started,
    end_date::TIMESTAMP AS ts_ended,
    year,
    month,
    day
FROM
    datalake_astro_raw.dag_run
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
