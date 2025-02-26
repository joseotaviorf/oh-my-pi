SELECT
    id AS id_log,
    dag_id AS id_dag,
    task_id AS id_task,
    run_id AS id_run,
    event,
    extra,
    owner,
    owner_display_name,
    map_index,
    try_number,
    dttm::TIMESTAMP AS ts_event,
    execution_date::TIMESTAMP AS ts_executed,
    year,
    month,
    day
FROM
    datalake_astro_raw.log
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
