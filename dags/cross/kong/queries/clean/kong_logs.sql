SELECT
    kl.app,
    kl.cluster_name,
    kl.container_name,
    kl.env,
    kl.message,
    kl.namespace,
    kl.pod_name,
    kl.stream,
    kl.time AS ts_event,
    kl.year,
    kl.month,
    kl.day,
    kl.hour
  FROM
    datalake_kong_raw.kong_logs AS kl
  WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
