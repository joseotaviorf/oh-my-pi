WITH alerts_updated AS (
  SELECT
    id_alert,
    dt_load,
    year,
    month,
    day
  FROM (
    SELECT
      al.id_alert,
      al.dt_load,
      al.year,
      al.month,
      al.day,
      ROW_NUMBER() OVER (PARTITION BY al.id_alert ORDER BY al.dt_load DESC) AS _w
    FROM datalake_jira_ops_clean.alert_log AS al
    WHERE
      MAKE_DATE(al.year, al.month, al.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  ) AS _t
  WHERE
    1 = _w
), alert_log AS (
  SELECT
    al.id_alert,
    al.log_type,
    al.log,
    al.owner,
    al.ts_log,
    au.dt_load,
    au.year,
    au.month,
    au.day
  FROM datalake_jira_ops_clean.alert_log AS al
  JOIN alerts_updated AS au
    ON al.id_alert = au.id_alert
), get_alert_actions AS (
  SELECT
    id_alert,
    log_type,
    owner,
    TRIM(SPLIT(SPLIT(log, 'via')[0], 'Alert ')[1]) AS action,
    TRIM(SPLIT(SPLIT(SPLIT(log, 'via')[1], '\\\\[')[0], '\\\\.')[0]) AS direction,
    ts_log
  FROM alert_log
  WHERE
    log LIKE 'Alert%'
  GROUP BY ALL
), filter_alert_actions AS (
  SELECT
    id_alert,
    FIRST(owner) FILTER(WHERE
      action = 'acknowledged') AS acknowledged_by,
    FIRST(owner) FILTER(WHERE
      action = 'closed') AS closed_by,
    MIN(ts_log) FILTER(WHERE
      action = 'acknowledged') AS ts_acknowledged,
    MIN(ts_log) FILTER(WHERE
      action = 'closed') AS ts_closed
  FROM get_alert_actions AS gaa
  WHERE
    action IN ('acknowledged', 'closed')
  GROUP BY ALL
), get_alert_notification AS (
  SELECT
    id_alert,
    log_type,
    owner AS log_owner,
    log,
    REGEXP_EXTRACT(log, 'Rule\\\\[([^\\\\]]+)\\\\]') AS rule_name,
    REGEXP_EXTRACT(log, 'Rule\\\\[[^\\\\]]+\\\\]\\\\[([^\\\\]]+)\\\\]') AS rule_action,
    REGEXP_EXTRACT(log, 'Rule\\\\[[^\\\\]]+\\\\]\\\\[[^\\\\]]+\\\\]\\\\[([^\\\\]]+)\\\\]') AS rule_step,
    CASE
      WHEN log RLIKE '->\\\\s*Sent'
      THEN 'Sent'
      WHEN log RLIKE '->\\\\s*Received'
      THEN 'Received'
      WHEN log RLIKE '->\\\\s*An aggregated'
      THEN 'Aggregated'
      WHEN log RLIKE '->\\\\s*\\\\[.*\\\\]\\\\s*notification.*submitted'
      THEN 'Submitted'
      ELSE NULL
    END AS direction,
    REGEXP_EXTRACT(log, '\\\\[?(email|sms|voice)\\\\]?') AS notification_type,
    ts_log
  FROM alert_log
  WHERE
    log LIKE '%notification%'
  GROUP BY ALL
), get_alert_out_of_rotation AS (
  SELECT
    id_alert,
    TRUE AS is_out_of_rotation,
    MIN(ts_log) FILTER(WHERE
      log RLIKE '(?i)^Will close alert automatically.*Auto-Close out-of-rotation time') AS ts_out_of_rotation_identified,
    MIN(ts_log) FILTER(WHERE
      log RLIKE '(?i)^Alert closed via system.*Auto-Close out-of-rotation time') AS ts_out_of_rotation_closed
  FROM alert_log
  WHERE
    log LIKE '%[Auto-Close out-of-rotation time]%'
  GROUP BY ALL
), get_alert_dei_automation AS (
  SELECT
    l.id_alert,
    IF(
      REGEXP_EXTRACT(l.log, 'ExecutionStatus\\\\[([^\\\\]]+)\\\\]') = 'succeed',
      SUBSTRING_INDEX(SUBSTRING_INDEX(l.log, 'key: [', -1), ']', 1),
      NULL
    ) AS id_issue_jira,
    NULLIF(REGEXP_EXTRACT(l.log, 'ExecutionStatus\\\\[([^\\\\]]+)\\\\]'), '') AS card_creation_status,
    REGEXP_EXTRACT(l.log, 'ExecutionStatus\\\\[([^\\\\]]+)\\\\]') = 'failed' AS is_card_creation_failed
  FROM alert_log AS l
  WHERE
    l.log RLIKE 'AE - DEI Automation'
), get_alert_dei_automation_exception_1 AS (
  SELECT
    l.id_alert,
    NULLIF(REGEXP_EXTRACT(l.log, '\\\\{{[^=]+=(DEI-[0-9]+)\\\\}}'), '') AS id_issue_jira
  FROM alert_log AS l
  WHERE
    l.log RLIKE '\\\\{{issueKey'
), get_alert_dei_automation_exception_2 AS (
  SELECT
    l.id_alert,
    NULLIF(SUBSTRING_INDEX(SUBSTRING_INDEX(l.log, 'key: [', -1), ']', 1), '') AS id_issue_jira
  FROM alert_log AS l
  WHERE
    l.log LIKE '%key: [DEI-%]'
), filter_dei_automation AS (
  SELECT
    id_alert,
    id_issue_jira,
    card_creation_status,
    is_card_creation_failed
  FROM (
    SELECT
      gad.id_alert,
      CASE
        WHEN gad.id_issue_jira RLIKE '^DEI-[0-9]+$'
        THEN gad.id_issue_jira
        ELSE COALESCE(exception_1.id_issue_jira, exception_2.id_issue_jira)
      END AS id_issue_jira,
      gad.card_creation_status,
      gad.is_card_creation_failed,
      ROW_NUMBER() OVER (PARTITION BY gad.id_alert ORDER BY CAST(gad.is_card_creation_failed AS SMALLINT)) AS _w
    FROM get_alert_dei_automation AS gad
    LEFT JOIN get_alert_dei_automation_exception_1 AS exception_1
      ON exception_1.id_alert = gad.id_alert
    LEFT JOIN get_alert_dei_automation_exception_2 AS exception_2
      ON exception_2.id_alert = gad.id_alert
  ) AS _t
  WHERE
    1 = _w
)
SELECT
  a.id_alert,
  fda.id_issue_jira,
  aa.closed_by,
  aa.acknowledged_by,
  fda.card_creation_status,
  NOT MIN(an.ts_log) FILTER(WHERE
    an.direction = 'Sent' AND an.notification_type = 'voice') IS NULL AS is_call_notification_sent,
  NOT MIN(an.ts_log) FILTER(WHERE
    an.direction = 'Sent' AND an.notification_type = 'email') IS NULL AS is_email_notification_sent,
  COALESCE(aor.is_out_of_rotation, FALSE) AS is_out_of_rotation,
  COALESCE(fda.is_card_creation_failed, FALSE) AS is_card_creation_failed,
  aa.ts_acknowledged,
  aa.ts_closed,
  aor.ts_out_of_rotation_identified,
  aor.ts_out_of_rotation_closed,
  MIN(an.ts_log) FILTER(WHERE
    an.direction = 'Sent' AND an.notification_type = 'voice') AS ts_first_call_notification_sent,
  MAX(an.ts_log) FILTER(WHERE
    an.direction = 'Sent' AND an.notification_type = 'voice') AS ts_last_call_notification_sent,
  MIN(an.ts_log) FILTER(WHERE
    an.direction = 'Sent' AND an.notification_type = 'email') AS ts_first_email_notification_sent,
  MAX(an.ts_log) FILTER(WHERE
    an.direction = 'Sent' AND an.notification_type = 'email') AS ts_last_email_notification_sent,
  a.dt_load AS dt_updated,
  a.year,
  a.month,
  a.day
FROM alert_log AS a
LEFT JOIN filter_alert_actions AS aa
  ON a.id_alert = aa.id_alert
LEFT JOIN get_alert_notification AS an
  ON aa.id_alert = an.id_alert
LEFT JOIN get_alert_out_of_rotation AS aor
  ON a.id_alert = aor.id_alert
LEFT JOIN filter_dei_automation AS fda
  ON a.id_alert = fda.id_alert
GROUP BY ALL