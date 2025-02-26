SELECT
    id AS id_fail,
    dag_id AS id_dag,
    task_id AS id_task,
    run_id AS id_run,
    map_index,
    duration,
    start_date::TIMESTAMP AS ts_started,
    end_date::TIMESTAMP AS ts_ended,
    year,
    month,
    day
FROM
    datalake_astro_raw.task_fail
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
