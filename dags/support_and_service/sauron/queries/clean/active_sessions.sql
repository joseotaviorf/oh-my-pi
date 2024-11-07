SELECT
  id,
  agent,
  status,
  user_data,
  user_phone,
  context,
  created_by,
  last_message_at AS ts_last_message,
  first_message_at AS ts_first_message,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sauron_raw.activesessions
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
