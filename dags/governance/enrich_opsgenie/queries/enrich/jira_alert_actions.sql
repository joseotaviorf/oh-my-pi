WITH get_alert_actions AS (
  SELECT
    id_alert,
    log_type,
    owner,
    TRIM(SPLIT(SPLIT(log, 'via') [0], 'Alert ') [1]) AS action,
    TRIM(
      SPLIT(SPLIT(SPLIT(log, 'via') [1], '\\[') [0], '\\.') [0]
    ) AS direction,
    ts_log
  FROM
    datalake_jira_ops_clean.alert_log
  WHERE
    log LIKE "Alert%"
  GROUP BY
    ALL
),
get_alert_notification AS (
  SELECT
    id_alert,
    log_type,
    owner AS log_owner,
    log,
    REGEXP_EXTRACT(log, 'Rule\\[([^\\]]+)\\]', 1) AS rule_name,
    REGEXP_EXTRACT(log, 'Rule\\[[^\\]]+\\]\\[([^\\]]+)\\]', 1) AS rule_action,
    REGEXP_EXTRACT(
      log,
      'Rule\\[[^\\]]+\\]\\[[^\\]]+\\]\\[([^\\]]+)\\]',
      1
    ) AS rule_step,
    CASE
      WHEN log RLIKE '->\\s*Sent' THEN 'Sent'
      WHEN log RLIKE '->\\s*Received' THEN 'Received'
      WHEN log RLIKE '->\\s*An aggregated' THEN 'Aggregated'
      WHEN log RLIKE '->\\s*\\[.*\\]\\s*notification.*submitted' THEN 'Submitted'
      ELSE NULL
    END AS direction,
    REGEXP_EXTRACT(log, '\\[?(email|sms|voice)\\]?', 1) AS notification_type,
    ts_log
  FROM
    datalake_jira_ops_clean.alert_log
  WHERE
    log LIKE "%notification%"
  GROUP BY
    ALL
),
filter_alert_actions AS (
  SELECT
    id_alert,
    FIRST(owner) FILTER(WHERE action = 'acknowledged') AS acknowledged_by,
    FIRST(owner) FILTER(WHERE action = 'closed') AS closed_by,
    MIN(ts_log) FILTER(WHERE action = 'acknowledged') AS ts_acknowledged,
    MIN(ts_log) FILTER(WHERE action = 'closed') AS ts_closed
  FROM
    get_alert_actions
  WHERE
    action IN ('acknowledged', 'closed')
  GROUP BY ALL
)
SELECT
  aa.id_alert,
  aa.closed_by,
  aa.acknowledged_by,
  MIN(an.ts_log) FILTER(WHERE an.direction = 'Sent' AND an.notification_type = 'voice') IS NOT NULL AS is_call_notification_sent,
  MIN(an.ts_log) FILTER(WHERE an.direction = 'Sent' AND an.notification_type = 'email') IS NOT NULL AS is_email_notification_sent,
  aa.ts_acknowledged,
  aa.ts_closed,
  MIN(an.ts_log) FILTER(WHERE an.direction = 'Sent' AND an.notification_type = 'voice') AS ts_first_call_notification_sent,
  MAX(an.ts_log) FILTER(WHERE an.direction = 'Sent' AND an.notification_type = 'voice') AS ts_last_call_notification_sent,
  MIN(an.ts_log) FILTER(WHERE an.direction = 'Sent' AND an.notification_type = 'email') AS ts_first_email_notification_sent,
  MAX(an.ts_log) FILTER(WHERE an.direction = 'Sent' AND an.notification_type = 'email') AS ts_last_email_notification_sent
FROM
  filter_alert_actions AS aa
LEFT JOIN
  get_alert_notification AS an
    ON aa.id_alert = an.id_alert
GROUP BY ALL
