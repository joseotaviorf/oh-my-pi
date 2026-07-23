WITH actions_updated AS (
  SELECT
    a.id_alert,
    a.dt_updated
  FROM
    datalake_opsgenie.jira_alert_actions AS a
  WHERE
    MAKE_DATE(a.year, a.month, a.day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
alerts AS (
  SELECT
    a.id_alert,
    a.id_alias,
    COALESCE(
      NULLIF(REGEXP_REPLACE(element_at(tags, 1), '[\\\[\\\]]', ''), ''),
      NULLIF(REGEXP_EXTRACT(a.message, 'DAG:\\\s*(.*?)\\\s*-\\\s*Task', 1), ''),
      NULLIF(REGEXP_EXTRACT(a.message, 'workflow_name=([^ }}]+)', 1), '')
    ) AS dag_name,
    COALESCE(
      NULLIF(REGEXP_REPLACE(element_at(a.tags, 3), '\]$', ''), ''),
      NULLIF(REGEXP_EXTRACT(a.message, 'Task:\\\s*(.*)$', 1), '')
    ) AS task_name,
    NULLIF(TRIM(a.owner), '') AS owned_by,
    a.status,
    a.is_seen,
    a.is_acknowledged,
    a.is_snoozed,
    IF(a.status = 'closed', TRUE, FALSE) AS is_closed,
    a.ts_created,
    FROM_UTC_TIMESTAMP(a.ts_created, 'America/Sao_Paulo') AS ts_created_local_tz,
    a.ts_updated,
    FROM_UTC_TIMESTAMP(a.ts_updated, 'America/Sao_Paulo') AS ts_updated_local_tz,
    TIMESTAMP(ja.dt_updated) AS ts_last_action_updated,
    FROM_UTC_TIMESTAMP(ja.dt_updated, 'America/Sao_Paulo') AS ts_last_action_updated_local_tz,
    a.year,
    a.month,
    a.day
  FROM
    datalake_jira_ops_clean.alerts AS a
  LEFT JOIN
    actions_updated AS ja
      ON a.id_alert = ja.id_alert
  WHERE
    MAKE_DATE(a.year, a.month, a.day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
    OR ja.id_alert IS NOT NULL
  QUALIFY 
    1 = ROW_NUMBER() OVER (PARTITION BY a.id_alert ORDER BY GREATEST(a.ts_updated, TIMESTAMP(ja.dt_updated)) DESC)
)
SELECT
  a.id_alert,
  a.id_alias,
  COALESCE(ja.id_issue_jira, i.id_issue) AS id_issue_jira,
  a.dag_name,
  a.task_name,
  a.owned_by,
  ja.acknowledged_by,
  ja.closed_by,
  a.status,
  a.is_seen,
  a.is_acknowledged,
  a.is_snoozed,
  a.is_closed,
  ja.is_out_of_rotation,
  ja.is_card_creation_failed,
  COALESCE(ja.is_call_notification_sent, FALSE) AS has_call_notification_made,
  COALESCE(ja.is_email_notification_sent, FALSE) AS has_email_notification_sent,
  ja.is_call_notification_sent IS TRUE OR ja.is_email_notification_sent IS TRUE AS has_notification_sent,
  ja.ts_acknowledged,
  FROM_UTC_TIMESTAMP(ja.ts_acknowledged, 'America/Sao_Paulo') AS ts_acknowledged_local_tz,
  ja.ts_closed,
  FROM_UTC_TIMESTAMP(ja.ts_closed, 'America/Sao_Paulo') AS ts_closed_local_tz,
  a.ts_created,
  a.ts_created_local_tz,
  GREATEST(a.ts_updated, a.ts_last_action_updated) AS ts_updated,
  GREATEST(a.ts_updated_local_tz, a.ts_last_action_updated_local_tz) AS ts_updated_local_tz,
  a.year,
  a.month,
  a.day
FROM
  alerts AS a
LEFT JOIN
  datalake_opsgenie.jira_alert_actions AS ja
    ON a.id_alert = ja.id_alert
LEFT JOIN
    datalake_jira.issues AS i
      ON ja.id_issue_jira IS NULL
      AND i.summary = a.dag_name
      AND i.ts_created BETWEEN ts_created_local_tz AND ts_created_local_tz + INTERVAL 10 MINUTE
GROUP BY ALL