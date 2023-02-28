SELECT
    dag_id AS id_dag,
    data AS json_data,
    CAST(last_updated AS TIMESTAMP) AS ts_last_updated
FROM
    datalake_composer_raw.serialized_dag
