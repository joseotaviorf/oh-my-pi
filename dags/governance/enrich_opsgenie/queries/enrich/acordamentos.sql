WITH 
extracted_log AS (
  SELECT 
    l.id,
    SUBSTRING_INDEX(SUBSTRING_INDEX(l.log, 'key: [', -1), ']', 1) AS id_issue_jira
  FROM
    datalake_opsgenie_clean.logs AS l
  WHERE
    l.log LIKE '%key: [DEI-%]'
),
alerts AS (
  SELECT
    a.id,
    a.dag_name,
    a.acknowledged_by,
    a.is_acknowledged,
    a.ts_created, 
    LAG(a.dag_name) OVER (ORDER BY a.ts_created ASC) AS previous_dag
  FROM
    datalake_opsgenie_clean.alerts AS a 
),
ordered_alerts AS (
  SELECT 
    a.id,
    el.id_issue_jira,
    a.dag_name,
    a.acknowledged_by,
    a.is_acknowledged,
    MAX(l.is_email_notification_sent) AS has_email_notification_sent,
    MAX(l.is_call_notification_made) AS has_call_notification_made,
    a.ts_created,
    a.previous_dag,
    SUM(CASE WHEN a.dag_name != a.previous_dag THEN 1 ELSE 0 END) 
    OVER (ORDER BY a.ts_created ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS dag_alert_group
  FROM
    alerts AS a
  INNER JOIN
    datalake_opsgenie_clean.logs AS l
      ON a.id = l.id
  LEFT JOIN
    extracted_log AS el
      ON a.id = el.id
  GROUP BY
    ALL
)
  SELECT
    oa.dag_alert_group AS id_incident,
    MAX(oa.id_issue_jira) AS id_issue_jira,
    oa.dag_name,
    FIRST_VALUE(oa.acknowledged_by) AS acknowledged_by,
    MAX(oa.is_acknowledged) AS is_acknowledged,
    MAX(oa.has_email_notification_sent) AS has_email_notification_sent,
    MAX(oa.has_call_notification_made) AS has_call_notification_made,
    MIN(FROM_UTC_TIMESTAMP(oa.ts_created, 'America/Sao_Paulo')) AS ts_first_alert,
    MAX(FROM_UTC_TIMESTAMP(oa.ts_created, 'America/Sao_Paulo')) AS ts_last_alert
  FROM 
    ordered_alerts AS oa
  WHERE
    oa.dag_name IS NOT NULL
      AND REGEXP_REPLACE(oa.dag_name, '\\s+', '') != ''
  GROUP BY
    ALL