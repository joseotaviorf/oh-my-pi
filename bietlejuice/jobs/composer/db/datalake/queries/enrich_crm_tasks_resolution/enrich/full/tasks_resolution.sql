WITH last_updated_task AS (
  SELECT
    *,
    MAX(DATE(CONCAT( year,'-', month,'-', day))) OVER (PARTITION BY id) AS dt_last_updated
  FROM
    datalake_crm.tasks
)
SELECT DISTINCT
  lut.id AS id_task,
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
  tsk.id_workgroup,
  id_user_action,
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
  action_user_name,
  action_type,
  is_resolved,
  ts_start,
  ts_completed,
  dt_visit,
  ts_created,
  ts_silenced_until,
  ts_origin,
  ts_fup,
  ts_action,
  tac.year,
  tac.month,
  tac.day
FROM
  last_updated_task lut
INNER JOIN
  datalake_crm.tasks_actions tac
    ON lut.id = tac.id_task
WHERE
  DATE(CONCAT(lut.year,'-',lut.month,'-',lut.day)) = lut.dt_last_updated