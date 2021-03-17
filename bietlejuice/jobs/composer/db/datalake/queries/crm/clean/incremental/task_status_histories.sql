SELECT
  _id AS id,
  history,
  __v AS version,
  year,
  month,
  day
FROM
  datalake_crm_raw.taskstatushistories
WHERE 
  year = {year}
  AND month = {month}
  AND day = {day}