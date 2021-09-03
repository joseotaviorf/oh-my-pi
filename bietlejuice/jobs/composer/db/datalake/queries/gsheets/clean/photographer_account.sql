SELECT
  CAST(id_photographer AS INTEGER) AS id_photographer,
  account_name,
  photographer_name,
  DATE(dt_start) AS dt_started,
  DATE(dt_end) AS dt_ended
FROM
  datalake_gsheets_raw.photographer_account
