SELECT
  id,
  name,
  NOW() AS ts_load,
  year,
  month,
  day
FROM 
  datalake_greenhouse_raw.close_reasons