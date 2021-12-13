SELECT
    id,
    dag_id AS id_dag,
    run_id AS id_run,
    conf AS configuration,
    state,
    CAST(external_trigger AS BOOLEAN) AS had_external_trigger,
    CAST(end_date AS TIMESTAMP) AS ts_ended,
    CAST(execution_date AS TIMESTAMP) AS ts_executed,
    CAST(start_date AS TIMESTAMP) AS ts_started
FROM
    datalake_composer_raw.dag_run