SELECT
    dag_id AS id_dag,
    data AS json_data,
    CAST(last_updated AS TIMESTAMP) AS ts_last_updated,
    year,
    month,
    day
FROM
    datalake_composer_raw.serialized_dag
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
