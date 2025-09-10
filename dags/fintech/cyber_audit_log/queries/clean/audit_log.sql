SELECT
    ALID AS id_audit_log,
    ALPATH AS path_called,
    ALMETHOD AS method_called,
    ALDATE AS ts_action,
    ALUSER AS id_user,
    ALIP AS ip_address,
    ALRECORD AS record_content,
    source,
    ts_ingestion,
    table_partition,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_cyber_audit_log_raw.audit_log
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
