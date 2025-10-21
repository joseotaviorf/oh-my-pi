WITH dataset_logs AS (
    SELECT
        id,
        SPLIT_PART(CAST(get_json_object(json, '$.path') AS STRING), '/', 5) AS id_dataset,
        json,
        MAKE_DATE(year, month, day) AS dt_event,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_superset_clean.logs
    WHERE
        action IN ('DatasetRestApi.get', 'DatasetRestApi.put')
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
dataset_executions AS (
    SELECT
        id_dataset,
        dt_event,
        COUNT(id) FILTER (WHERE DATE(ts_event) = dt_event) AS dataset_executions,
        year,
        month,
        day
    FROM
        dataset_logs
    GROUP BY ALL
)
SELECT
    hash(CONCAT(id_dataset, dt_event)) AS id_snapshot,
    id_dataset,
    dataset_executions,
    dt_event,
    year,
    month,
    day
FROM
    dataset_executions
