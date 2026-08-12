SELECT
  id,
  external_id AS id_external,
  session_id AS id_session,
  user_id AS id_user,
  idempotency_key AS id_idempotency,
  chunk_id AS id_chunk,
  message_index,
  role,
  channel,
  input_type,
  content,
  extra,
  processing_status,
  media_url,
  media_type,
  created_at AS ts_created
FROM
  datalake_copilot_service_raw.message
