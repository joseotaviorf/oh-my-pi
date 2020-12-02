SELECT
  id,
  session_id AS id_session,
  message_id AS id_message,
  message_payload,
  year_month,
  status,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sauron_raw.incoming_message_status
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
