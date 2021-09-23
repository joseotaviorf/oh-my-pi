WITH task_resolution_ranking AS (
  SELECT
    id_task,
    COALESCE(id_workgroup, -1) AS id_workgroup,
    type,
    ROW_NUMBER() OVER (PARTITION BY id_task, id_workgroup, type ORDER BY ts_action DESC) AS ranking,
    NULLIF(id_user_action, '') IS NULL AS is_task_auto_completed,
    ts_action
  FROM
    datalake_crm_tasks_resolution.tasks_resolution_history
  WHERE
    action_type in ('RESOLVE', 'REALIZE', 'FINISH', 'DISCARD')
    AND year = {year}
    AND month = {month}
    AND day = {day}
),
tasks_max_date AS (
  SELECT
      id,
      COALESCE(id_workgroup, -1) AS id_workgroup,
      type,
      MAX(DATE(CONCAT(year,'-', month,'-', day))) AS dt_last_updated
  FROM
      datalake_crm.tasks ct
  GROUP BY 1,2,3
)
SELECT DISTINCT
  t.id AS id_task,
  t.id_workgroup,
  CAST(t.score_factor AS INTEGER) AS score_factor,
  CAST(t.version AS INTEGER) AS version,
  t.origin AS origin,
  t.type AS type,
  t.description,
  t.subject AS subject,
  ROUND(
      (TO_UNIX_TIMESTAMP(COALESCE(tr.ts_action, t.ts_completed), 'yyyy-MM-dd HH:mm:ss') - TO_UNIX_TIMESTAMP(t.ts_start,'yyyy-MM-dd HH:mm:ss')) / 60.0,
      2
  ) AS hours_task_start_to_completed,
  t.is_resolved,
  COALESCE(tr.is_task_auto_completed, false) AS is_task_auto_completed,  
  t.ts_start,
  t.ts_completed,
  t.ts_silenced_until,
  CAST(COLLECT_SET(COALESCE(t.subject, cw.title)) OVER (PARTITION BY t.id) AS STRING) AS titles,
  CAST(COLLECT_SET(COALESCE(t.id_workgroup, cw.id)) OVER (PARTITION BY t.id) AS STRING) AS workgroups,
  t.year,
  t.month,
  t.day
FROM
  datalake_crm.tasks t
JOIN
  tasks_max_date md
    ON t.id = md.id
    AND COALESCE(t.id_workgroup, -1) = md.id_workgroup
    AND t.type = md.type
    AND DATE(CONCAT(year,'-', month,'-', day)) = md.dt_last_updated
LEFT JOIN
  datalake_crm.workgroups cw
    ON t.type = cw.task_type
LEFT JOIN
  task_resolution_ranking tr
    ON tr.id_task = t.id
    AND tr.id_workgroup = COALESCE(t.id_workgroup, -1)
    AND tr.type = t.type
    AND tr.ranking = 1
WHERE
  t.year = {year}
  AND t.month = {month}
  AND t.day = {day}