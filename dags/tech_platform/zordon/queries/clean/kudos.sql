SELECT
  id,
  principle_id AS id_principle,
  receiver_email,
  sender_email,
  message,
  receiver_info,
  message_info,
  created_at AS ts_created
FROM
  datalake_zordon_raw.kudos
