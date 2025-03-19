SELECT
  app,
  cluster_name,
  container_name,
  env,
  message,
  namespace,
  pod_name,
  stream,
  time AS ts_event,
  year,
  month,
  day,
  hour
FROM
  datalake_kong_raw.kong_logs
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
