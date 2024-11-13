SELECT
    alerts.fingerprint AS id,
    alerts.labels.cluster_name AS dag_name,
    alerts.labels.component AS cluster_component,
    commonAnnotations.message AS message,
    alerts.labels.alarm_channel AS alert_channel,
    alerts.labels.alertname AS alert_name,
    REGEXP_EXTRACT(commonAnnotations.message,"[0-9]\.?[0-9]?",0)::FLOAT AS alert_qty,
    REGEXP_EXTRACT(commonAnnotations.message,"(?<=[0-9])[a-zA-Z%]+",0)::STRING AS alert_unit,
    `@timestamp`::TIMESTAMP AS ts_alert,
    alerts.startsAt::TIMESTAMP AS ts_start,
    IF(YEAR(alerts.endsAt) == 1,NULL,alerts.endsAt)::TIMESTAMP AS ts_end,
    alerts.status AS status,
    year::INT,
    month::INT,
    day::INT
FROM
    datalake_alert_manager_raw.alerts
WHERE
    alerts.labels.app = 'databricks-clusters'
    AND DATE(`@timestamp`) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')    