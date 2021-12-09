SELECT
    id AS id_fail,
    dag_id AS id_dag,
    task_id AS id_task,
    duration,
    CAST(end_date AS TIMESTAMP) AS ts_ended,
    CAST(execution_date AS TIMESTAMP) AS ts_executed,
    CAST(start_date AS TIMESTAMP) AS ts_started
FROM
    datalake_composer_raw.task_fail