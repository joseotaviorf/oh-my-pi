SELECT
    rev,
    user_id AS id_user,
    trace_id AS id_trace,
    CAST(FROM_UNIXTIME(CAST(revtstmp AS BIGINT)/1000) AS TIMESTAMP) AS ts_rev
FROM
    datalake_docx_raw.revinfo
