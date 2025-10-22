SELECT
    id,
    url,
    status,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_quires_raw.urls
WHERE
    DATE(updatedAt) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')