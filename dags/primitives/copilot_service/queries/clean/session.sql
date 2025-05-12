SELECT
  id,
  external_id AS id_external,
  external_reference AS id_sauron_session,
  user_id AS id_user,
  chat_configuration,
  created_at AS ts_created
FROM
  datalake_copilot_service_raw.session
