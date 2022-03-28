SELECT
    id AS id_log,
    dag_id AS id_dag,
    task_id AS id_task,
    event,
    extra,
    owner,
    dttm AS ts_event,
    execution_date AS ts_executed,
    year,
    month,
    day
FROM
    datalake_composer_raw.log
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}