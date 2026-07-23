WITH alerts AS (
  SELECT
    a.id_alert,
    a.id_issue_jira,
    a.dag_name,
    a.is_acknowledged,
    a.acknowledged_by,
    a.has_call_notification_made,
    a.has_email_notification_sent,
    a.ts_created_local_tz,
    LAG(a.dag_name) OVER (ORDER BY a.ts_created_local_tz ASC) AS previous_dag
  FROM
    datalake_opsgenie.alerts AS a
),
ordered_alerts AS (
  SELECT
    a.id_alert,
    a.id_issue_jira,
    a.dag_name,
    a.acknowledged_by,
    a.is_acknowledged,
    a.has_call_notification_made,
    a.has_email_notification_sent,
    a.ts_created_local_tz,
    a.previous_dag,
    SUM(
      CASE 
        WHEN a.dag_name != a.previous_dag THEN 1 
        ELSE 0 
      END
    ) OVER (
      ORDER BY a.ts_created_local_tz ASC 
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS dag_alert_group
  FROM
    alerts AS a
  GROUP BY ALL
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
    MIN(oa.ts_created_local_tz) AS ts_first_alert,
    MAX(oa.ts_created_local_tz) AS ts_last_alert
  FROM
    ordered_alerts AS oa
  WHERE
    oa.dag_name IS NOT NULL
  GROUP BY ALL
)
SELECT
  id_incident,
  id_issue_jira,
  dag_name,
  acknowledged_by,
  is_acknowledged,
  has_email_notification_sent,
  has_call_notification_made,
  ts_first_alert,
  ts_last_alert
FROM
  get_acordamentos
