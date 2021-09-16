WITH tasks_resolution_history AS (
  WITH last_updated_task AS (
    SELECT
      id,
      MAX(DATE(CONCAT(year,'-',month,'-',day))) AS dt_last_updated
    FROM
      datalake_crm.tasks tsk
    GROUP BY 1
  )
  SELECT DISTINCT
    tsk.id AS id_task,
    COALESCE(tsh.id, tac.id) AS id_action,
    CASE
      WHEN tsh.id IS NOT NULL THEN tsh.id_user_action
      ELSE tac.id_user_action
    END AS id_user_action,
    tsk.id_assignee,
    tsk.id_house,
    tsk.id_rent_flow,
    tsk.id_origin,
    tsk.id_opened_by,
    tsk.id_tenant,
    tsk.id_negotiation,
    tsk.id_manager,
    tsk.id_owner,
    tsk.id_receiver,
    tsk.id_workgroup,
    CASE
      WHEN tsh.id IS NOT NULL THEN tsh.task_status
    END AS task_status,
    CASE
      WHEN tsh.id IS NOT NULL THEN tsh.action_reason
    END AS action_reason,
    CASE
      WHEN tsh.id IS NOT NULL THEN tsh.action_user_name
      ELSE tac.action_user_name
    END AS action_user_name,
    CASE
      WHEN tsh.id IS NOT NULL THEN tsh.action_type
      ELSE tac.action_type
    END AS action_type,
    tsk.type,
    tsk.version,
    tsk.tags,
    tsk.score,
    tsk.score_factor,
    tsk.receiver_name,
    tsk.receiver_type,
    tsk.task_comment,
    tsk.origin,
    tsk.description,
    tsk.phase,
    tsk.subject,
    tsk.visit_fup,
    tsk.is_resolved,
    CASE
      WHEN tsh.id IS NOT NULL THEN tsh.ts_action
      ELSE tac.ts_action
    END AS ts_action,
    tsk.ts_created,
    tsk.ts_start,
    tsk.ts_completed,
    tsk.dt_visit,
    tsk.ts_silenced_until,
    tsk.ts_origin,
    tsk.ts_fup,
    tsk.year,
    tsk.month,
    tsk.day
  FROM
    datalake_crm.tasks tsk
  INNER JOIN
    last_updated_task lut
        ON tsk.id = lut.id
        AND DATE(CONCAT(tsk.year,'-',tsk.month,'-',tsk.day)) = lut.dt_last_updated
  INNER JOIN
    datalake_crm.tasks_actions tac
        ON tsk.id=tac.id_task
  LEFT JOIN
    datalake_crm.task_status_histories tsh
        ON tsk.id = tsh.id_task  
)
SELECT
  id_task,
  id_action,
  id_user_action,
  id_assignee,
  id_house,
  id_rent_flow,
  id_origin,
  id_opened_by,
  id_tenant,
  id_negotiation,
  id_manager,
  id_owner,
  id_receiver,
  id_workgroup,
  task_status,
  action_reason,
  action_user_name,
  action_type,
  type,
  version,
  tags,
  score,
  score_factor,
  receiver_name,
  receiver_type,
  task_comment,
  origin,
  description,
  phase,
  subject,
  visit_fup,
  IF(
        action_user_name IS NULL,
        NULL,
        ROUND(
            (TO_UNIX_TIMESTAMP(LEAD(ts_action) OVER (PARTITION BY id_task ORDER BY ts_action),  'yyyy-MM-dd HH:mm:ss') - TO_UNIX_TIMESTAMP(ts_action, 'yyyy-MM-dd HH:mm:ss'))/3600.0,
            1
        )
  ) AS task_user_resolve_hours,
  is_resolved,
  ts_action,
  LAG(ts_action) OVER (PARTITION BY id_task ORDER BY ts_action) AS ts_previous_action,
  LEAD(ts_action) OVER (PARTITION BY id_task ORDER BY ts_action) AS ts_next_action,
  ts_created,
  ts_start,
  ts_completed,
  dt_visit,
  ts_silenced_until,
  ts_origin,
  ts_fup,
  year,
  month,
  day
FROM
  tasks_resolution_history