SELECT
    task_id,
    dag_id,
    state,
    duration,
    max_tries,
    try_number,
    end_date,
    execution_date,
    start_date
FROM
    task_instance
WHERE
    DATE(execution_date) >= NOW() - INTERVAL 2 MONTH -- DATE('{{ ds }}')