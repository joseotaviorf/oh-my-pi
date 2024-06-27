WITH extracted_log AS (
  SELECT 
    l.id,
    SUBSTRING_INDEX(SUBSTRING_INDEX(l.log, 'key: [', -1), ']', 1) AS id_issue_jira
  FROM
    datalake_opsgenie_clean.logs AS l
  WHERE 
    l.log LIKE '%key: [DEI-%]'
)
SELECT
  a.id,
  a.id_alias,
  el.id_issue_jira,
  a.dag_name,
  a.task_name,
  a.owned_by,
  a.acknowledged_by,
  a.closed_by,
  a.status,
  a.is_seen,
  a.is_acknowledged,
  a.is_snoozed,
  a.ts_closed IS NOT NULL AS is_closed,
  MAX(l.is_email_notification_sent) AS has_email_notification_sent,
  MAX(l.is_call_notification_made) AS has_call_notification_made,
  a.ts_created,
  a.ts_updated,
  a.ts_acknowledged,
  a.ts_closed,
  a.year,
  a.month,
  a.day
FROM
  datalake_opsgenie_clean.alerts AS a
INNER JOIN
  datalake_opsgenie_clean.logs AS l
    ON a.id = l.id
LEFT JOIN
  extracted_log AS el
    ON a.id = el.id
WHERE
  a.year = {year}
  AND a.month = {month}
  AND a.day = {day}
GROUP BY
  ALL
