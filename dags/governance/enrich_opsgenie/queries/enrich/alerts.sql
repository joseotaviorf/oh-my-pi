WITH extracted_log AS (
  SELECT
    l.id_alert,
    SUBSTRING_INDEX(SUBSTRING_INDEX(l.log, 'key: [', -1), ']', 1) AS id_issue_jira
  FROM
    datalake_jira_ops_clean.alert_log AS l
  WHERE
    l.log LIKE '%key: [DEI-%]'
), get_alerts AS (
SELECT
  a.id_alert,
  a.id_alias,
  el.id_issue_jira,
  element_at(tags, 1) AS dag_name,
  element_at(tags, 3) AS task_name,
  a.owner AS owned_by,
  ja.acknowledged_by,
  ja.closed_by,
  a.status,
  a.is_seen,
  a.is_acknowledged,
  a.is_snoozed,
  IF(a.status = 'closed', TRUE, FALSE) AS is_closed,
  ja.is_call_notification_sent AS has_call_notification_made,
  ja.is_email_notification_sent AS has_email_notification_sent,
  a.ts_created,
  a.ts_updated,
  ja.ts_acknowledged,
  ja.ts_closed,
  a.year,
  a.month,
  a.day
FROM
  datalake_jira_ops_clean.alerts AS a
INNER JOIN
  datalake_jira_ops_clean.alert_log AS l
    ON a.id_alert = l.id_alert
LEFT JOIN
  extracted_log AS el
    ON a.id_alert = el.id_alert
LEFT JOIN
  datalake_opsgenie.jira_alert_actions AS ja
    ON a.id_alert = ja.id_alert
GROUP BY ALL
)
SELECT
  id_alert,
  id_alias,
  id_issue_jira,
  REGEXP_REPLACE(dag_name,'^\\[', '') AS dag_name,
  REGEXP_REPLACE(task_name, '\]$', '') AS task_name,
  owned_by,
  acknowledged_by,
  closed_by,
  status,
  is_seen,
  is_acknowledged,
  is_snoozed,
  is_closed,
  has_call_notification_made,
  has_email_notification_sent,
  ts_created,
  ts_updated,
  ts_acknowledged,
  ts_closed,
  year,
  month,
  day
FROM
  get_alerts
GROUP BY
  ALL
