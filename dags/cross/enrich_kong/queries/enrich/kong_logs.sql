SELECT
  app,
  cluster_name,
  container_name,
  env,
  message,
  namespace,
  pod_name,
  stream,
  REGEXP_EXTRACT(message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 1) AS client_ip,
  REGEXP_EXTRACT(message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 2) AS request_user,
  REGEXP_EXTRACT(message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 3) AS request_host,
  REGEXP_EXTRACT(message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 4) AS request_method,
  REGEXP_EXTRACT(message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 5) AS request_uri,
  REGEXP_EXTRACT(message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 6) AS response_code,
  ts_event,
  year,
  month,
  day,
  hour
FROM
  datalake_kong_clean.kong_logs
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  AND message NOT LIKE "%[warn]%"
  AND message NOT LIKE "%[notice]%"
