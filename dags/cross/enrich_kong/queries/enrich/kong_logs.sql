SELECT
  kl.app,
  kl.cluster_name,
  kl.container_name,
  kl.env,
  kl.message,
  kl.namespace,
  kl.pod_name,
  kl.stream,
  REGEXP_EXTRACT(kl.message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 1) as client_ip,
  REGEXP_EXTRACT(kl.message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 2) as request_user,
  REGEXP_EXTRACT(kl.message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 3) as request_host,
  REGEXP_EXTRACT(kl.message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 4) as request_method,
  REGEXP_EXTRACT(kl.message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 5) as request_uri,
  REGEXP_EXTRACT(kl.message, "^(.*) \- (.*) \- \\[.*\\] (.*) \"(.*) (.*)\" (\\d+)", 6) as response_code,
  kl.ts_event,
  kl.year,
  kl.month,
  kl.day,
  kl.hour
FROM
  datalake_kong_clean.kong_logs AS kl
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
  AND message NOT LIKE "%[warn]%"
  AND message NOT LIKE "%[notice]%"
