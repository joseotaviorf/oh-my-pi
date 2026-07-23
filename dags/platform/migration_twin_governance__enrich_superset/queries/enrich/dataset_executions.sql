WITH dataset_logs AS (
    SELECT
        id,
        SPLIT_PART(CAST(get_json_object(json, '$.path') AS STRING), '/', 5) AS id_dataset,
        json,
        DATE(ts_event) AS dt_event,
        ts_event
    FROM
        datalake_superset_clean.logs
    WHERE
        action IN ('DatasetRestApi.get', 'DatasetRestApi.put')
        AND DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
dataset_executions AS (
    SELECT
        id_dataset,
        dt_event,
        COUNT(id) AS dataset_executions
    FROM
        dataset_logs
    GROUP BY ALL
)
SELECT
    hash(CONCAT(id_dataset, dt_event)) AS id_snapshot,
    id_dataset,
    dataset_executions,
    dt_event,
    YEAR(dt_event) AS year,
    MONTH(dt_event) AS month,
    DAY(dt_event) AS day
FROM
    dataset_executions
