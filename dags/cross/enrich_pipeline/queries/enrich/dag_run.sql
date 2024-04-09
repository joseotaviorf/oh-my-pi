WITH first_run_ever AS (
  -- The first run of a DAG shouldn't be considered to calculate our SLA, so it's important to mark it
  SELECT
    id_dag,
    ts_executed
  FROM
    datalake_composer_clean.log
  WHERE
    id_dag LIKE 'bietlejuice%'
    AND id_task IN ('create-cluster', 'execute-job-cluster')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_dag ORDER BY ts_event ASC) = 1
),
success_run AS (
  -- Checking the first time that the DAG run was marked as successful
  SELECT
    id_dag,
    ts_event AS ts_success_event,
    ts_executed
  FROM
    datalake_composer_clean.log
  WHERE
    id_dag LIKE 'bietlejuice%'
    AND event = 'success'
    AND id_task IN ('terminate-cluster', 'job-cluster-finished')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_dag, ts_executed ORDER BY ts_event ASC) = 1
),
dag_clear AS (
  -- Checking if the DAG run suffered any clear, which indicates that it ran more than once
  SELECT DISTINCT
    id_dag,
    ts_executed
  FROM
    datalake_composer_clean.log
  WHERE
    id_dag LIKE 'bietlejuice%'
    AND event = 'dagrun_clear'
)
SELECT
  dr.id AS id_dag_run,
  dr.id_dag,
  dr.id_run,
  dr.state,
  ROUND((UNIX_TIMESTAMP(dr.ts_ended) - UNIX_TIMESTAMP(dr.ts_started))/60, 0) AS duration,
  dr.had_external_trigger,
  IF(dr.id_run LIKE 'mediator%', TRUE, FALSE) AS is_triggered_by_mediator,
  IF(fre.id_dag IS NOT NULL, TRUE, FALSE) AS is_first_run_ever,
  IF(dr.state = 'failed', FALSE, TRUE) AS is_run_successful,
  CASE
    WHEN fre.id_dag IS NULL THEN 
        (
          CASE
            WHEN dr.id_dag LIKE '%.enrich_%'
              OR dr.id_dag LIKE '%.metric_%'
              OR (dr.id_dag LIKE '%.dw_%'
                AND dr.id_dag NOT LIKE '%datamarts%') THEN
            (
              CASE
                WHEN s.ts_success_event <= TO_TIMESTAMP(CURRENT_DATE, 'yyyy-MM-dd HH:mm:ss') + INTERVAL 11 HOUR THEN TRUE
                ELSE FALSE
              END
            )
        ELSE
            (
              CASE
                WHEN dr.id_dag LIKE '%datamarts%' AND s.ts_success_event <= TO_TIMESTAMP(CURRENT_DATE, 'yyyy-MM-dd HH:mm:ss') + INTERVAL 13 HOUR THEN TRUE
                ELSE FALSE
              END
            )
          END
        )
    ELSE NULL
  END AS is_first_execution_inside_sla,
  IF(c.id_dag IS NOT NULL, TRUE, FALSE) AS has_been_cleared,
  dr.ts_executed AS ts_execution,
  dr.ts_started,
  dr.ts_ended,
  s.ts_success_event AS ts_first_execution_success
FROM
  datalake_composer_clean.dag_run AS dr
JOIN
  datalake_composer_clean.dag AS d
    ON d.id_dag = dr.id_dag
    AND d.id_dag LIKE 'bietlejuice%'
LEFT JOIN
  first_run_ever AS fre
    ON fre.id_dag = dr.id_dag
    AND fre.ts_executed = dr.ts_executed
LEFT JOIN
  success_run AS s
    ON s.id_dag = dr.id_dag
    AND s.ts_executed = dr.ts_executed
LEFT JOIN
  dag_clear AS c
    ON c.id_dag = dr.id_dag
    AND c.ts_executed = dr.ts_executed