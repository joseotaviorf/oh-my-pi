WITH tasks_resolution_max_date AS (
  SELECT
    id_task,
    id_workgroup,
    type,
    ROW_NUMBER() OVER (PARTITION BY id_task, id_workgroup, type ORDER BY ts_action DESC) AS ranking,
    NULLIF(id_user_action, '') IS NULL AS is_task_auto_completed,
    ts_action
  FROM
    datalake_crm_tasks_resolution.tasks_resolution
  WHERE
    action_type IN ('RESOLVE', 'REALIZE')
    AND year = {year}
    AND month = {month}
    AND day = {day}
),
tasks_max_date AS (
  SELECT
    id,
    id_workgroup,
    type,
    MAX(DATE(CONCAT(year,'-', month,'-', day))) AS dt_last_updated
  FROM
    datalake_crm.tasks
  GROUP BY 1, 2, 3
)
SELECT DISTINCT
  ct.id AS id_task,
  ct.id_workgroup,
  ct.score_factor,
  ct.version,
  ct.origin,
  ct.type,
  SUBSTR(description, 1, 4000) AS description,
  ct.subject,
  CAST(COLLECT_SET(COALESCE(ct.subject, cw.title)) OVER (PARTITION BY ct.id) AS STRING) AS titles,
  CAST(COLLECT_SET(COALESCE(ct.id_workgroup, cw.id)) OVER (PARTITION BY ct.id) AS STRING) AS workgroups,
  ROUND((
    UNIX_TIMESTAMP(trm.ts_action) - UNIX_TIMESTAMP(ct.ts_start)
  ) / 3600, 2) AS hours_task_started_to_completed,
  ct.is_resolved,
  COALESCE(trm.is_task_auto_completed, FALSE) AS is_task_auto_completed,
  ct.ts_start AS ts_started,
  COALESCE(trm.ts_action, ct.ts_completed) AS ts_completed,
  ct.ts_silenced_until,
  ct.ts_completed AS ts_partition,
  ct.year,
  ct.month,
  ct.day
FROM
  datalake_crm.tasks AS ct
  JOIN
    tasks_max_date AS tmd
      ON ct.id = tmd.id
        AND ct.id_workgroup = tmd.id_workgroup
        AND ct.type = tmd.type
        AND DATE(CONCAT(ct.year,'-', ct.month,'-', ct.day)) = tmd.dt_last_updated
  LEFT JOIN
    datalake_crm.workgroups AS cw 
      ON ct.type = cw.task_type
  LEFT JOIN
    tasks_resolution_max_date AS trm
      ON ct.id = trm.id_task
        AND trm.id_workgroup = ct.id_workgroup
        AND trm.type = ct.type
        AND trm.ranking = 1
WHERE
  ct.year = {year}
  AND ct.month = {month}
  AND ct.day = {day}