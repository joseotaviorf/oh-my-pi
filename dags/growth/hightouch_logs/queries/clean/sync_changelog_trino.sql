WITH ranked AS (
    SELECT
        CAST(sct.sync_id AS STRING) AS id_sync,
        CAST(sct.sync_run_id AS STRING) AS id_sync_run,
        CAST(sct.row_id AS STRING) AS id_row,
        CAST(sct.op_type AS STRING) AS op_type,
        CAST(sct.status AS STRING) AS status,
        CAST(sct.failure_reason AS STRING) AS failure_reason,
        sct.fields AS fields,
        sct.year AS year,
        sct.month AS month,
        sct.day AS day,
        ROW_NUMBER() OVER (
            PARTITION BY
                CAST(sct.sync_id AS STRING),
                CAST(sct.sync_run_id AS STRING),
                CAST(sct.row_id AS STRING)
            ORDER BY MAKE_DATE(sct.year, sct.month, sct.day) DESC
        ) AS rn
    FROM
        datalake_hightouch_logs_raw.sync_changelog_trino AS sct
    WHERE
        MAKE_DATE(sct.year, sct.month, sct.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_sync,
    id_sync_run,
    id_row,
    op_type,
    status,
    failure_reason,
    fields,
    year,
    month,
    day
FROM ranked
WHERE rn = 1
