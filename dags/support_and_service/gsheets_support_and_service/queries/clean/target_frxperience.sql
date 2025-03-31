SELECT
  birdie_opportunity,
  top_offender,
  client_type,
  metric_name,
  CAST(value AS DOUBLE) AS target,
  metric_type,
  quarter,
  DATE(date_ref) AS dt_target
FROM
  datalake_gsheets_raw.target_frxperience