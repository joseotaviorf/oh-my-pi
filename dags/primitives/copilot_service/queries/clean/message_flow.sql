SELECT
  id,
  message_id AS id_message,
  flow,
  created_at AS ts_created
FROM datalake_copilot_service_raw.message_flow
