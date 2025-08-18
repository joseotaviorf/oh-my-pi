SELECT
  ji.id_issue AS id_issue_jira,
  oa.id_alert,
  ji.summary AS dag_name,
  pl.line_name AS dag_owner,
  ji.incident_owner,
  pl.layer,
  ji.current_status,
  ji.incident_category,
  ji.root_cause_resolution AS incident_root_cause_resolution,
  ji.incident_status AS oncall_incident_status,
  ji.issue_description,
  ji.assignee AS user_assigned,
  SPLIT(oa.acknowledged_by, '@')[0] AS user_acknowledged,
  (ji.assignee IS NOT NULL) AS is_assigned,
  oa.is_acknowledged,
  ji.root_cause_resolution = 'Not an incident' AS is_not_an_incident,
  (ji.ts_resolved IS NULL) AS is_open,
  (ji.ts_resolved IS NOT NULL) AS is_resolved,
  CASE
    WHEN ji.incident_owner <> 'AE All'
      AND ji.incident_owner IS NOT NULL
      AND ji.incident_status <> 'Under investigation' -- on call status
      AND ji.assignee IS NOT NULL
      AND ji.incident_category IS NOT NULL
      AND ji.root_cause_resolution <> 'Discovery'
      THEN TRUE
    ELSE FALSE
  END AS is_card_filled,
  oa.has_notification_sent,
  oa.has_call_notification_made AS has_call_notification_sent,
  oa.has_email_notification_sent,
  ji.root_cause_resolution IS NOT NULL AS has_root_cause_filled,
  ji.incident_category IS NOT NULL AS has_incident_category_filled,
  ji.is_deleted,
  ji.is_deleted IS True AND DATE(ji.ts_created) >= DATE('2025-06-01') AS is_deleted_duplicate,
  ji.dt_deleted,
  ji.dt_started,
  ji.ts_created,
  ji.ts_resolved,
  ji.ts_updated,
  NOW() AS ts_load,
  aux.quarter,
  aux.year,
  aux.month,
  aux.day
FROM
  datalake_jira.issues AS ji
LEFT JOIN
  datalake_opsgenie.alerts AS oa
    ON ji.id_issue = oa.id_issue_jira
LEFT JOIN
  datalake_pipeline.dag AS pl
    ON ji.summary = pl.id_dag
LEFT JOIN
  datalake_quintoandar.aux_date AS aux
    ON DATE(ji.ts_created) = aux.date
WHERE
  ji.id_project = '11446'