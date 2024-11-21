SELECT
  id,
  call_id AS id_call,
  message_id AS id_message,
  call_payload,
  user_phone,
  year_month,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sauron_raw.callevents
