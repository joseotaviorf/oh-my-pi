SELECT
  CAST(id_owner AS BIGINT) AS id_owner,
  CAST(id_user AS BIGINT) AS id_user,
  email,
  first_name,
  last_name,
  teams,
  is_archived,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM datalake_hubspot_clean.owner
WHERE
  year = STRUCT(year AS year)
  AND month = STRUCT(month AS month)
  AND day = STRUCT(day AS day)