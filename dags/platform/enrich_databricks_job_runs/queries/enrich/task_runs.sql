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
    jr.task_runtime.startTS::TIMESTAMP AS ts_task_started,
    jr.task_runtime.endTS::TIMESTAMP AS ts_task_ended,
    YEAR(jr.task_runtime.startTS::TIMESTAMP) AS year,
    MONTH(jr.task_runtime.startTS::TIMESTAMP) AS month,
    DAY(jr.task_runtime.startTS::TIMESTAMP) AS day
FROM
    overwatch.jobrun AS jr
JOIN
    datalake_databricks.unique_clusters AS uc
        ON jr.cluster_id = uc.id_cluster
WHERE
    uc.bietlejuice_dag_name IS NOT NULL
    AND jr.task_runtime.startTS::TIMESTAMP BETWEEN '{load_start_date}' AND '{load_end_date}'