SELECT
  id AS id_message,
  incremental_id AS id_incremental,
  destination,
  headers,
  payload,
  published,
  FROM_UNIXTIME(creation_time/1000) AS ts_creation,
  YEAR(ts_creation) AS year,
  MONTH(ts_creation) AS month,
  DAY(ts_creation) as day
FROM
  datalake_demand_contact_submission_raw.message
