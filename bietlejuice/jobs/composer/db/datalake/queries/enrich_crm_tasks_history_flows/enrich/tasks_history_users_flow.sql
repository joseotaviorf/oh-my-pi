WITH actions AS (
  SELECT
    trh.id_task,
    COALESCE(CAST(trh.id_receiver AS BIGINT), -1) AS id_receiver,
    COALESCE(CAST(trh.id_origin AS BIGINT), -1) AS id_origin,
    COALESCE(CAST(trh.id_assignee AS BIGINT), -1) AS id_assignee,
    COALESCE(CAST(trh.id_user_action AS BIGINT), -1) AS id_user_action,
    COALESCE(trh.id_workgroup, -1) AS id_workgroup,
    COALESCE(CAST(DATE_FORMAT(ts_start, 'yyyyMMdd') AS BIGINT), -1) AS id_start_date,
    COALESCE(CAST(DATE_FORMAT(ts_action, 'yyyyMMdd') AS BIGINT), -1) AS id_action_date,
    COALESCE(CAST(DATE_FORMAT(ts_next_action, 'yyyyMMdd') AS BIGINT), -1) AS id_next_action_date,
    COALESCE(CAST(DATE_FORMAT(ts_completed, 'yyyyMMdd') AS BIGINT), -1) AS id_completed_date,
    trh.action_user_name,
    trh.action_type,
    trh.action_reason,
    trh.task_status,
    trh.type,
    ts_action,
    COALESCE(
        CAST(trh.task_user_resolve_hours AS DOUBLE),
        ROUND((
            TO_UNIX_TIMESTAMP(lead(trh.ts_action) OVER (PARTITION BY trh.id_task ORDER BY trh.ts_action), 'yyyy-MM-dd HH:mm:ss')
            - TO_UNIX_TIMESTAMP(trh.ts_action, 'yyyy-MM-dd HH:mm:ss')
        )/3600.0, 1)
    ) AS task_user_resolve_hours,
    trh.ts_action,
    trh.ts_next_action,
    year,
    month,
    day
  FROM
    datalake_crm_tasks_resolution.tasks_resolution_history trh
  WHERE 
    year = {year}
    AND month = {month}
    AND day = {day}
),
most_recent_completed_task_by_user AS (
  SELECT
    a.id_task,
    a.id_user_action,
    a.id_next_action_date,
    a.id_action_date,
    a.id_workgroup,
    a.type,
    a.action_type,
    a.task_user_resolve_hours,
    a.ts_next_action,
    a.ts_action,
    ROW_NUMBER() OVER (PARTITION BY a.id_task, a.id_user_action ORDER BY a.ts_action DESC) AS ranking
  FROM
    actions a
  WHERE
    a.action_type IN ('REALIZE', 'FINISH')
    AND a.id_user_action != -1
),
create_start_actions AS (
  SELECT
      id_task,
      MIN(CAST(CASE WHEN action_type = 'CREATE' THEN ts_action END AS TIMESTAMP)) AS ts_created_task,
      MIN(CAST(CASE WHEN action_type = 'START' THEN ts_action END AS TIMESTAMP)) AS ts_started_task
  FROM
      actions
  GROUP BY 1
)
SELECT DISTINCT
  a.id_task,
  a.id_receiver,
  a.id_origin,
  a.id_assignee,
  a.id_user_action,
  a.id_start_date,
  a.id_completed_date,
  COALESCE(mrbu.id_next_action_date, a.id_next_action_date) AS id_next_action_date,
  COALESCE(mrbu.id_action_date, a.id_action_date) AS id_action_date,
  a.id_workgroup,
  a.type,
  a.action_user_name,
  a.action_type,
  a.action_reason,
  a.task_status,
  ROUND(
    (TO_UNIX_TIMESTAMP(csa.ts_started_task, 'yyyy-MM-dd HH:mm:ss') - TO_UNIX_TIMESTAMP(csa.ts_created_task, 'yyyy-MM-dd HH:mm:ss'))/60.0,
    1
  ) AS minutes_task_created_to_started,
  COALESCE(mrbu.task_user_resolve_hours, a.task_user_resolve_hours) AS task_user_resolve_hours,
  COALESCE(mrbu.ts_next_action, a.ts_next_action) AS ts_next_action,
  COALESCE(mrbu.ts_action, a.ts_action) AS ts_action,
  DATE(CONCAT(year,'-',month,'-',day)) AS dt_partition,
  year,
  month,
  day
FROM
    actions a
LEFT JOIN
  create_start_actions csa
    ON a.id_task = csa.id_task
LEFT JOIN
  most_recent_completed_task_by_user mrbu
    ON a.id_task = mrbu.id_task
    AND a.id_user_action = mrbu.id_user_action
    AND a.action_type = mrbu.action_type
    AND mrbu.ranking = 1
WHERE
  -- due to a bug in CRM, the status REALIZE might have no user attached to it
  -- that scenario should only be possible with the RESOLVE status.
  NOT (a.id_user_action = -1 AND a.action_type = 'REALIZE')