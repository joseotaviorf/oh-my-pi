WITH tasks_resolution_max_date AS (
  SELECT
    id_task,
    id_user_action,
    FIRST_VALUE(ts_analyst_started, TRUE) OVER(PARTITION BY id_task ORDER BY ts_action) AS ts_analyst_started_array,
    MAX(ts_action) OVER(PARTITION BY id_task) AS ts_max_action,
    ts_action
  FROM
    datalake_crm.tasks_actions
  WHERE
    action_type IN ('RESOLVE', 'REALIZE')
    AND year = {year}
    AND month = {month}
    AND day = {day}
),
last_updated_actions AS (
  SELECT
    id_task,
    IF(id_user_action IS NOT NULL, FALSE, TRUE) AS is_task_auto_completed,
    ts_max_action,
    MIN(ts_analyst_started_array) AS ts_min_analyst_started
  FROM
    tasks_resolution_max_date
  WHERE
    ts_action = ts_max_action
  GROUP BY 1, 2, 3
)
SELECT
  ct.id AS id_task,
  ct.id_workgroup,
  ct.score_factor,
  ct.version,
  ct.origin,
  ct.type,
  SUBSTR(description, 1, 4000) AS description,
  ct.subject,
  COLLECT_SET(COALESCE(ct.subject, cw.title)) AS titles,
  COLLECT_SET(COALESCE(ct.id_workgroup, cw.id)) AS workgroups,
  ROUND((
    UNIX_TIMESTAMP(lua.ts_max_action) - UNIX_TIMESTAMP(ct.ts_start)
  ) / 3600, 2) AS hours_task_started_to_completed,
  ct.is_resolved,
  COALESCE(lua.is_task_auto_completed, FALSE) AS is_task_auto_completed,
  ct.ts_start AS ts_started,
  COALESCE(lua.ts_max_action, ct.ts_completed) AS ts_completed,
  ct.ts_silenced_until,
  lua.ts_min_analyst_started AS ts_analyst_started,
  ct.ts_completed AS ts_partition,
  ct.year,
  ct.month,
  ct.day
FROM
  datalake_crm.tasks AS ct
  JOIN
    last_updated_actions AS lua 
      ON ct.id = lua.id_task
        AND DATE(CONCAT(ct.year,'-', ct.month,'-', ct.day)) = DATE(lua.ts_max_action)
  LEFT JOIN
    datalake_crm.workgroups AS cw 
      ON ct.type = cw.task_type
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21