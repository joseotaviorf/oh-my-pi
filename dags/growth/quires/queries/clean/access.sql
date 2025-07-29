SELECT
    id,
    plate,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    year,
    month,
    day
FROM
    datalake_quires_raw.access
WHERE
    DATE(createdAt) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')