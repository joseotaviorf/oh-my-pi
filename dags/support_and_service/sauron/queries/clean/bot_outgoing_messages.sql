SELECT
  id,
  message_id AS id_message,
  incoming_message_id AS id_incoming_message,
  session_id AS id_session,
  message_payload,
  bot_response,
  user_phone,
  year_month,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sauron_raw.botoutgoingmessages
