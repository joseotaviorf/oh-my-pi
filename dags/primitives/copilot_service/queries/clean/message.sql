SELECT
  id,
  external_id AS id_external,
  session_id AS id_session,
  message_index,
  role,
  channel,
  input_type,
  content,
  extra,
  created_at AS ts_created
FROM
  datalake_copilot_service_raw.message
