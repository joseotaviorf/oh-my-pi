SELECT
    CAST(sync_id AS STRING) AS id_sync,
    CAST(sync_run_id AS STRING) AS id_sync_run,
    CAST(row_id AS STRING) AS id_row,
    CAST(op_type AS STRING) AS op_type,
    CAST(status AS STRING) AS status,
    CAST(failure_reason AS STRING) AS failure_reason

FROM
    datalake_hightouch_logs_raw.sync_changelog_databricks
