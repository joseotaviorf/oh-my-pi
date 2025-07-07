with main as (SELECT
  CAST(GET_JSON_OBJECT(kubernetes, '$.pod_labels') AS STRING) AS pod_labels,
  cluster_name,
  CAST(GET_JSON_OBJECT(kubernetes, '$.container_name') AS STRING) AS container_name,
  message,
  CAST(GET_JSON_OBJECT(kubernetes, '$.pod_namespace') AS STRING) AS namespace,
  CAST(GET_JSON_OBJECT(kubernetes, '$.pod_namespace') AS STRING) AS env,
  CAST(GET_JSON_OBJECT(kubernetes, '$.pod_name') AS STRING) AS pod_name,
  stream,
  timestamp as ts_event,
  year,
  month,
  day,
  hour
FROM
  datalake_kong_raw.kong_logs
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  )
SELECT 
  CAST(GET_JSON_OBJECT(pod_labels, '$.app') AS STRING) AS app,
  cluster_name,
  container_name,
  env,
  message, 
  namespace,
  pod_name,
  stream,
  ts_event,
  year,
  month,
  day,
  hour
FROM 
  main