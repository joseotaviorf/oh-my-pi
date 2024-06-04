SELECT
  id_task,
  id_reservation,
  id_worker,
  id_user,
  id_session,
  user_phone,
  REPLACE(GET_JSON_OBJECT(task_attributes,'$.name'), "Call In-App | ", "") AS user_email,
  communication_channel,
  bpo_name,
  queue_name,
  task_attributes,
  ts_created,
  ts_updated
FROM
  datalake_bigfone_clean.scheduled_call_task
