SELECT
    alerts.fingerprint::STRING AS id,
    alerts.labels.alarm_channel::STRING AS alert_channel,
    alerts.labels.alertname::STRING AS alert_name,
    alerts.labels.app::STRING AS alert_app,
    alerts.status::STRING AS status,
    alerts.labels.severity::STRING AS severity,
    commonLabels.line::STRING AS line,
    alerts.startsAt::TIMESTAMP AS ts_start,
    IF(YEAR(alerts.endsAt) == 1,NULL,alerts.endsAt)::TIMESTAMP AS ts_end,
    `@timestamp`::TIMESTAMP AS ts_alert,
    year,
    month,
    day
FROM 
    datalake_alert_manager_raw.alerts
WHERE
    DATE(`@timestamp`) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')    