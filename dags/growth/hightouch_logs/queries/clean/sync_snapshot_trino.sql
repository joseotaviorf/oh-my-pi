SELECT
    CAST(s.sync_id AS STRING) AS id_sync,
    CAST(s.row_id AS STRING) AS id_row,
    CAST(s.op_type AS STRING) AS op_type,
    CAST(s.status AS STRING) AS status,
    CAST(s.failure_reason AS STRING) AS failure_reason,
    CAST(s.fields AS STRING) AS model_fields_json,
    r.ts_started AS ts_started,
    r.ts_finished AS ts_finished,
    r.year AS year,
    r.month AS month,
    r.day AS day
FROM
    datalake_hightouch_logs_raw.sync_snapshot_trino AS s
INNER JOIN datalake_hightouch_logs_clean.sync_runs_trino AS r
    ON CAST(s.sync_id AS STRING) = r.id_sync
WHERE
    CAST(r.ts_started AS DATE) BETWEEN '{load_start_date}' AND '{load_end_date}'
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY CAST(s.sync_id AS STRING), CAST(s.row_id AS STRING)
        ORDER BY r.ts_started DESC
    ) = 1
