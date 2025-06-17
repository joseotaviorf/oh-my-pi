SELECT
    alert_id AS id_alert,
    logType AS log_type,
    log,
    owner,
    TIMESTAMP(logTime) AS ts_log,
    dt_load,
    year,
    month,
    day
FROM
    datalake_jira_ops_raw.alert_log
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
