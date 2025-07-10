SELECT
  id,
  session_id AS id_session,
  message_id AS id_message,
  state_version,
  flow,
  state,
  created_at AS ts_created
FROM
  datalake_copilot_service_raw.state
