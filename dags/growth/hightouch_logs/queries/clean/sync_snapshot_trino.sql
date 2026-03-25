SELECT
    CAST(s.sync_id AS STRING) AS id_sync,
    CAST(s.row_id AS STRING) AS id_row,
    CAST(s.op_type AS STRING) AS op_type,
    CAST(s.status AS STRING) AS status,
    CAST(s.failure_reason AS STRING) AS failure_reason,
    CAST(s.fields AS STRING) AS model_fields_json,
    s.year AS year,
    s.month AS month,
    s.day AS day
FROM
    datalake_hightouch_logs_raw.sync_snapshot_trino AS s
WHERE
    MAKE_DATE(s.year, s.month, s.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY CAST(s.sync_id AS STRING), CAST(s.row_id AS STRING)
        ORDER BY MAKE_DATE(s.year, s.month, s.day) DESC, CAST(s.row_id AS STRING) DESC
    ) = 1
