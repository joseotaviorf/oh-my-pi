WITH dag_layer AS (
  SELECT DISTINCT
    dag,
    CASE
      WHEN CONCAT_WS('|', ARRAY_SORT(ARRAY_DISTINCT(COLLECT_LIST(layer)))) LIKE 'clean%'
      THEN 'clean|raw'
      ELSE CONCAT_WS('|', ARRAY_SORT(ARRAY_DISTINCT(COLLECT_LIST(layer))))
    END AS layer
  FROM datalake_dag_inventory_clean.table
  GROUP BY
    1
), dag_names AS (
  SELECT DISTINCT
    id_dag,
    REGEXP_REPLACE(owners, '(airflow|\\,)', '') AS dag_owner,
    layer AS dag_layer,
    CAST(adt.date AS DATE) AS dt_executed
  FROM datalake_airflow.dag AS dag
  LEFT JOIN dag_layer AS layer
    ON dag.id_dag = layer.dag
  CROSS JOIN datalake_quintoandar.aux_date AS adt
  WHERE
    dag.is_paused = FALSE
    AND adt.date >= CAST('2021-01-01' AS DATE)
    AND adt.date <= CURRENT_DATE
), execution_logs AS (
  SELECT
    dag.id_dag,
    dag.dag_owner,
    dag.dag_layer,
    dag.dt_executed,
    MIN(
      IF(
        log.event = 'running'
        AND log.id_task IN ('create-cluster', 'execute-job-cluster'),
        log.id_log,
        NULL
      )
    ) AS id_log_first_task,
    MIN(
      IF(
        log.event = 'success'
        AND log.id_task IN ('terminate-cluster', 'job-cluster-finished'),
        log.id_log,
        NULL
      )
    ) AS id_log_last_task
  FROM dag_names AS dag
  INNER JOIN datalake_airflow.log AS log
    ON log.id_dag = dag.id_dag
    AND CAST(log.ts_executed AS DATE) = dag.dt_executed - INTERVAL '1' DAY
    AND CAST(log.ts_event AS DATE) = dag.dt_executed
  WHERE
    log.event IN ('success', 'running')
  GROUP BY
    1,
    2,
    3,
    4
)
SELECT
  exec.id_dag AS dag_name,
  exec.dag_owner,
  exec.dag_layer,
  exec.dt_executed,
  log_started.ts_event AS ts_dag_started,
  log_last_task.ts_event AS ts_dag_ended,
  TIMESTAMPDIFF(MINUTE, TO_DATE(log_started.ts_event), TO_DATE(log_last_task.ts_event)) AS duration_in_minutes
FROM execution_logs AS exec
JOIN datalake_airflow.log AS log_started
  ON log_started.id_dag = exec.id_dag
  AND log_started.id_log = exec.id_log_first_task
  AND log_started.event = 'running'
  AND /* Due to new composer instance */ CAST(log_started.ts_event AS DATE) > CAST(exec.dt_executed - INTERVAL '2' DAY AS DATE)
JOIN datalake_airflow.log AS log_last_task
  ON log_last_task.id_dag = exec.id_dag
  AND log_last_task.id_log = exec.id_log_last_task
  AND log_last_task.event = 'success'
  AND /* Due to new composer instance */ CAST(log_last_task.ts_event AS DATE) > CAST(exec.dt_executed - INTERVAL '2' DAY AS DATE)