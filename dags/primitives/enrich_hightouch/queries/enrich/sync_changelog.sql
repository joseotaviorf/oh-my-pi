SELECT
    id_sync,
    id_sync_run,
    id_row,
    op_type,
    status,
    failure_reason

FROM
    datalake_hightouch_logs_clean.sync_changelog_databricks

UNION ALL

SELECT
    id_sync,
    id_sync_run,
    id_row,
    op_type,
    status,
    failure_reason

FROM
    datalake_hightouch_logs_clean.sync_changelog_trino
