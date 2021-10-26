WITH last_task_update AS (
  SELECT 
    id,
    MAX(DATE(CONCAT(year,'-',month,'-',day))) AS dt_last_updated
  FROM
    datalake_crm.tasks
  GROUP BY 1
),
actions_metrics as (
  SELECT
    id_task,
    SUM(CASE WHEN action_type = 'SNOOZE' THEN 1 ELSE 0 END) AS number_of_reschedules,
    COLLECT_SET(action_type) AS action_set,
    MAX(CASE WHEN action_type = 'RESOLVE' THEN ts_action ELSE NULL END) AS ts_closed
  FROM
    datalake_crm.tasks_actions
  GROUP BY 1
),
rep_info AS (
  SELECT DISTINCT
    id_task,
    FIRST(metadata_old_value, TRUE) OVER (PARTITION BY id_task ORDER BY ts_action RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS id_first_rep
  FROM
    datalake_crm.tasks_actions
  WHERE
     metadata_key='/assigneeId'
     AND action_type='UPDATE'
     AND metadata_old_value IS NOT NULL
)
SELECT DISTINCT
  t.id AS id_task,
  CAST(t.id_assignee AS BIGINT) AS id_rep,
  t.id_origin AS id_lead,
  CAST(COALESCE(ri.id_first_rep, t.id_assignee, -1) AS BIGINT) AS id_first_rep,
  t.type,
  am.number_of_reschedules,
  CASE
    WHEN CAST(am.action_set AS STRING) LIKE '%RESOLVE%' OR t.ts_completed IS NOT NULL THEN 'Closed'
    WHEN t.ts_silenced_until IS NOT NULL THEN 'Rescheduled'
    ELSE 'Open'
  END AS task_status,
  t.ts_start AS ts_created,
  COALESCE(am.ts_closed, t.ts_completed) AS ts_closed
FROM
  datalake_crm.tasks t
JOIN
  last_task_update ltu
    ON t.id = ltu.id
    AND DATE(CONCAT(t.year,'-',t.month,'-',t.day)) = ltu.dt_last_updated
JOIN
  actions_metrics am
    ON t.id = am.id_task
LEFT JOIN
  rep_info ri
    ON t.id = ri.id_task
WHERE
  t.type IN ("ConverterLead", "ConverterLeadPrioritario")
