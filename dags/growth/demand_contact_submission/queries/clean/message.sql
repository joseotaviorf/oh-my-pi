SELECT
  id AS id_message,
  incremental_id AS id_incremental,
  destination,
  headers,
  payload,
  published,
  FROM_UNIXTIME(creation_time/1000) AS ts_creation,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_raw.message
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
