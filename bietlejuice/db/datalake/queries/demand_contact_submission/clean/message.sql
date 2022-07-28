SELECT 
  id AS id_message,
  incremental_id AS id_incremental,
  destination,
  headers,
  payload,
  published,
  FROM_UNIXTIME(creation_time/1000) as ts_creation,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_raw.message
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}