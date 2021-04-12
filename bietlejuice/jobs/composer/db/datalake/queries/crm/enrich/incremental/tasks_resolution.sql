SELECT DISTINCT
  tsk.id AS id_task,
  tac.id AS id_action,
  id_rent_flow,
  id_origin,
  id_assignee,
  id_owner,
  id_house,
  id_opened_by,
  id_tenant,
  id_negotiation,
  id_manager,
  id_user_analyst,
  id_receiver,
  score_factor,
  receiver_name,
  task_comment,
  score,
  origin,
  type,
  receiver_type,
  description,
  phase,
  subject,
  tags,
  visit_fup,
  version,
  analyst_username,
  action_type AS task_user_type,
  is_resolved,
  ts_start,
  ts_completed,
  ts_visit,
  ts_created,
  ts_silenced_until,
  ts_origin,
  ts_fup,
  ts_action
FROM
  datalake_crm.tasks tsk
INNER JOIN
  datalake_crm.tasks_actions tac
    ON tsk.id = tac.id_task
    AND tac.year={year}
    AND tac.month={month}
    AND tac.day={day}