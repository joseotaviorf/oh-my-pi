WITH task_resolution_ranking AS (
  SELECT
    id_task,
    COALESCE(id_workgroup, -1) AS id_workgroup,
    ROW_NUMBER() OVER (PARTITION BY id_task, id_workgroup ORDER BY ts_action DESC) AS ranking,
    NULLIF(id_user_action, '') IS NULL AS is_task_auto_completed,
    ts_action
  FROM datalake_crm_tasks_resolution.tasks_resolution_history
  WHERE
    action_type IN ('RESOLVE', 'REALIZE', 'FINISH', 'DISCARD')
    AND year = STRUCT(year AS year)
    AND month = STRUCT(month AS month)
    AND day = STRUCT(day AS day)
), tasks_max_date AS (
  SELECT
    id,
    COALESCE(id_workgroup, -1) AS id_workgroup,
    MAX(CAST(CONCAT(year, '-', month, '-', day) AS DATE)) AS dt_last_updated
  FROM datalake_crm.tasks AS ct
  GROUP BY
    1,
    2
)
SELECT DISTINCT
  t.id AS id_task,
  t.id_workgroup,
  CAST(t.score_factor AS INT) AS score_factor,
  CAST(t.version AS INT) AS version,
  t.origin AS origin,
  t.type AS type,
  SUBSTRING(t.description, 1, 4000) AS description,
  t.subject AS subject,
  COLLECT_SET(COALESCE(t.subject, cw.title)) OVER (PARTITION BY t.id) AS titles,
  COLLECT_SET(COALESCE(t.id_workgroup, cw.id)) OVER (PARTITION BY t.id) AS workgroups,
  CAST(ROUND(
    (
      UNIX_TIMESTAMP(COALESCE(tr.ts_action, t.ts_completed)) - UNIX_TIMESTAMP(t.ts_start)
    ) / 60.0,
    2
  ) AS DECIMAL(10, 2)) AS hours_task_start_to_completed,
  t.is_resolved,
  COALESCE(tr.is_task_auto_completed, FALSE) AS is_task_auto_completed,
  DATE_TRUNC('SECOND', t.ts_start) AS ts_start,
  DATE_TRUNC('SECOND', t.ts_completed) AS ts_completed,
  DATE_TRUNC('SECOND', t.ts_silenced_until) AS ts_silenced_until,
  t.year,
  t.month,
  t.day
FROM datalake_crm.tasks AS t
JOIN tasks_max_date AS md
  ON t.id = md.id
  AND COALESCE(t.id_workgroup, -1) = md.id_workgroup
  AND CAST(CONCAT(year, '-', month, '-', day) AS DATE) = md.dt_last_updated
LEFT JOIN datalake_crm.workgroups AS cw
  ON t.type = cw.task_type
LEFT JOIN task_resolution_ranking AS tr
  ON tr.id_task = t.id
  AND tr.id_workgroup = COALESCE(t.id_workgroup, -1)
  AND tr.ranking = 1
WHERE
  t.year = STRUCT(year AS year)
  AND t.month = STRUCT(month AS month)
  AND t.day = STRUCT(day AS day)