SELECT
    id_dag,
    owners,
    schedule_interval,
    is_active,
    is_paused,
    source_provider,
    CURRENT_TIMESTAMP() AS ts_validated
FROM
    datalake_airflow.dag AS dag
WHERE
    is_active = TRUE
