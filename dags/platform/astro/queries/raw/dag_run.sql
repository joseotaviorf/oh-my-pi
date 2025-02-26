SELECT
    id,
    dag_id,
    queued_at,
    execution_date,
    start_date,
    end_date,
    state,
    run_id,
    creating_job_id,
    external_trigger,
    run_type,
    CAST(conf AS VARCHAR) AS conf,
    data_interval_start,
    data_interval_end,
    last_scheduling_decision,
    dag_hash,
    log_template_id,
    updated_at,
    clear_number
FROM
    dag_run
WHERE
    updated_at >= DATE('{load_start_date}')
    AND updated_at <= DATE('{load_end_date}')
