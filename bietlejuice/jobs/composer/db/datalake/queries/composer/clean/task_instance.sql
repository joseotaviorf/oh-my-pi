SELECT
    dag_id AS id_dag,
    task_id AS id_task,
    state AS task_state,
    duration,
    max_tries,
    try_number,
    CAST(end_date AS TIMESTAMP) AS ts_ended,
    CAST(execution_date AS TIMESTAMP) AS ts_executed,
    CAST(start_date AS TIMESTAMP) AS ts_started,
    year,
    month,
    day
FROM
    datalake_composer_raw.task_instance
WHERE
    DATE(execution_date) >= DATE(CONCAT({year}, '-', {month}, '-', {day}))