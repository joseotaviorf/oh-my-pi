WITH
extracted_log AS (
  SELECT
    l.id_alert,
    SUBSTRING_INDEX(SUBSTRING_INDEX(l.log, 'key: [', -1), ']', 1) AS id_issue_jira
  FROM
    datalake_jira_ops_clean.alert_log AS l
  WHERE
    l.log LIKE '%key: [DEI-%]'
),
alerts AS (
  SELECT
    a.id_alert,
    element_at(tags, 1) AS dag_name,
    a.is_acknowledged,
    a.ts_created,
    LAG(element_at(a.tags, 1)) OVER (ORDER BY a.ts_created ASC) AS previous_dag
  FROM
    datalake_jira_ops_clean.alerts AS a
),
ordered_alerts AS (
  SELECT
    a.id_alert,
    el.id_issue_jira,
    a.dag_name,
    ja.acknowledged_by,
    a.is_acknowledged,
    ja.is_call_notification_sent AS has_call_notification_made,
    ja.is_email_notification_sent AS has_email_notification_sent,
    a.ts_created,
    a.previous_dag,
    SUM(CASE WHEN a.dag_name != a.previous_dag THEN 1 ELSE 0 END)
    OVER (ORDER BY a.ts_created ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS dag_alert_group
  FROM
    alerts AS a
  INNER JOIN
    datalake_jira_ops_clean.alert_log AS l
      ON a.id_alert = l.id_alert
  LEFT JOIN
    extracted_log AS el
      ON a.id_alert = el.id_alert
  LEFT JOIN
    datalake_opsgenie.jira_alert_actions AS ja
      ON a.id_alert = ja.id_alert
  GROUP BY
    ALL
),
get_acordamentos AS (
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
)
SELECT
  id_incident,
  id_issue_jira,
  REGEXP_REPLACE(dag_name, '^\\[', '') AS dag_name,
  acknowledged_by,
  is_acknowledged,
  has_email_notification_sent,
  has_call_notification_made,
  ts_first_alert,
  ts_last_alert
FROM
  get_acordamentos
