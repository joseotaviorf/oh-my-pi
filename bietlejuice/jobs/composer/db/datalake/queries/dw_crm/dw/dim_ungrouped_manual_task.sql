SELECT
  id_task AS sk_task,
  score_factor,
  version,
  origin,
  type,
  description,
  subject,
  CAST(titles AS STRING) AS titles,
  CAST(workgroups AS STRING) AS workgroups,
  hours_task_started_to_completed,
  is_resolved,
  is_task_auto_completed,
  ts_started,
  ts_completed,
  ts_silenced_until,
  ts_partition,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_crm_tasks_flows.tasks_actions_resolutions_flow
WHERE
  type = 'Manual'
  AND id_workgroup IS NULL
  AND year = {year}
  AND month = {month}
  AND day = {month}