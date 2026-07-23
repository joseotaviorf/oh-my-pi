SELECT
  jr.job_id AS id_job,
  jr.run_id AS id_run,
  uc.id_cluster,
  uc.bietlejuice_dag_name,
  jr.run_name,
  jr.terminal_state,
  jr.task_dependencies,
  jr.task_detail,
  jr.task_runtime.runTimeS AS execution_time_in_seconds,
  CAST(jr.task_runtime.startTS AS TIMESTAMP) AS ts_task_started,
  CAST(jr.task_runtime.endTS AS TIMESTAMP) AS ts_task_ended,
  YEAR(TO_DATE(CAST(jr.task_runtime.startTS AS TIMESTAMP))) AS year,
  MONTH(TO_DATE(CAST(jr.task_runtime.startTS AS TIMESTAMP))) AS month,
  DAY(TO_DATE(CAST(jr.task_runtime.startTS AS TIMESTAMP))) AS day
FROM overwatch.jobrun AS jr
JOIN datalake_databricks.unique_clusters AS uc
  ON jr.cluster_id = uc.id_cluster
WHERE
  NOT uc.bietlejuice_dag_name IS NULL
  AND CAST(jr.task_runtime.startTS AS TIMESTAMP) BETWEEN '{load_start_date}' AND '{load_end_date}'