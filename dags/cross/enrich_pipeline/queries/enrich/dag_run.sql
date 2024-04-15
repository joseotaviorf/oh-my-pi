WITH first_run_ever AS (
  -- The first run of a DAG shouldn't be considered to calculate our SLA, so it's important to mark it
  SELECT
    id_dag,
    ts_executed
  FROM
    datalake_composer_clean.log
  WHERE
    id_dag LIKE 'bietlejuice%'
    AND (id_task IN ('create-cluster', 'execute-job-cluster')
      OR id_task LIKE '%-skip-execution%')  -- Some DAGs may have as the first task a short-circuit that skips the cluster/job creation
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_dag ORDER BY ts_event ASC) = 1
),
success_run AS (
  -- Checking the first time that the DAG run was marked as successful, which will be used to understand if it's inside or not the SLA
  SELECT
    id_dag,
    ts_event AS ts_success_event,
    ts_executed
  FROM
    datalake_composer_clean.log
  WHERE
    id_dag LIKE 'bietlejuice%'
    AND event = 'success'
    AND (id_task IN ('terminate-cluster', 'job-cluster-finished')
      OR id_task LIKE '%-skip-execution%') -- Some DAGs may have as the first task a short-circuit that skips the cluster/job creation
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
),
composer_run AS (
  /** Finding the most recent run of the Composer DAG for each execution date.
    Composer is a DAG that runs D0 and several times a day, which means that if today is 2024-04-10, the execution date will also be 2024-04-10.
    On the next day (2024-04-11) in its first Composer extraction, it will extract the data related to the end of the day of the 2024-04-10.
    So in this case, the execution date 2024-04-10 will have as it last run marked as the date of 2024-04-11
  ***/ 
  SELECT
    DATE(ts_executed) AS dt_execution,
    MAX(ts_started) AS ts_last_execution_started,
    MAX(ts_ended) AS ts_last_execution_ended
  FROM
    datalake_composer_clean.dag_run
  WHERE
    id_dag = 'bietlejuice.composer'
    AND DATE(ts_executed) = DATE(ts_ended)  -- Making sure that for every DAG execution date, we'll have the last extraction of the same day
  GROUP BY 1
)
SELECT
  dr.id AS id_dag_run,
  dr.id_dag,
  dr.id_run,
  dr.state,
  ROUND((UNIX_TIMESTAMP(dr.ts_ended) - UNIX_TIMESTAMP(dr.ts_started))/60, 0) AS duration,
  IF(ds.dag IS NOT NULL, TRUE, FALSE) AS is_in_exclusion_list,
  dr.had_external_trigger,
  IF(dr.id_run LIKE 'mediator%', TRUE, FALSE) AS is_triggered_by_mediator,
  IF(dr.id_run LIKE 'manual%', TRUE, FALSE) AS is_manual_run,
  IF(fre.id_dag IS NOT NULL, TRUE, FALSE) AS is_first_run_ever,
  IF(dr.state = 'failed', FALSE, TRUE) AS is_run_successful,
  CASE
    WHEN fre.id_dag IS NULL THEN -- If the DAG isn't in its first run, we can consider it
      (
        CASE
          WHEN ds.dag IS NULL 
            AND dr.id_run NOT LIKE 'manual%' THEN  -- Checking if the DAG isn't in the list to be ignored and if it's not a manual run
          (
            CASE  -- Layers raw/clean, enrich, dw (except for datamarts) and metric has 8h AM BRT as SLA
              WHEN dr.id_dag NOT LIKE '%datamarts%'
                AND dr.id_dag NOT LIKE '%reverse%' THEN
              (
                CASE
                  WHEN s.ts_success_event IS NOT NULL AND s.ts_success_event <= TO_TIMESTAMP(DATE(s.ts_success_event), 'yyyy-MM-dd HH:mm:ss') + INTERVAL 11 HOUR THEN TRUE
                  WHEN s.ts_success_event IS NOT NULL AND s.ts_success_event > TO_TIMESTAMP(DATE(s.ts_success_event), 'yyyy-MM-dd HH:mm:ss') + INTERVAL 11 HOUR THEN FALSE
                  WHEN s.ts_success_event IS NULL AND NOW() > TO_TIMESTAMP(CURRENT_DATE, 'yyyy-MM-dd HH:mm:ss') + INTERVAL 11 HOUR THEN FALSE
                  ELSE NULL
                END
              )
              WHEN dr.id_dag LIKE '%datamarts%' THEN
                  (
                    CASE
                      WHEN s.ts_success_event IS NOT NULL AND s.ts_success_event <= TO_TIMESTAMP(DATE(s.ts_success_event), 'yyyy-MM-dd HH:mm:ss') + INTERVAL 13 HOUR THEN TRUE
                      WHEN s.ts_success_event IS NOT NULL AND s.ts_success_event > TO_TIMESTAMP(DATE(s.ts_success_event), 'yyyy-MM-dd HH:mm:ss') + INTERVAL 13 HOUR THEN TRUE
                      WHEN s.ts_success_event IS NULL AND NOW() > TO_TIMESTAMP(CURRENT_DATE, 'yyyy-MM-dd HH:mm:ss') + INTERVAL 13 HOUR THEN FALSE
                      ELSE NULL
                    END
                  )
              ELSE NULL
            END
          )
          ELSE NULL
        END
      )
    ELSE NULL -- If the DAG is in its first run, it doesn't have a SLA
  END AS is_first_execution_inside_sla,
  IF(c.id_dag IS NOT NULL, TRUE, FALSE) AS has_been_cleared,
  dr.ts_executed AS ts_execution,
  FROM_UTC_TIMESTAMP(dr.ts_executed, 'America/Sao_Paulo') AS ts_execution_brt,
  dr.ts_started,
  FROM_UTC_TIMESTAMP(dr.ts_started, 'America/Sao_Paulo') AS ts_started_brt,
  dr.ts_ended,
  FROM_UTC_TIMESTAMP(dr.ts_ended, 'America/Sao_Paulo') AS ts_ended_brt,
  s.ts_success_event AS ts_first_execution_success,
  FROM_UTC_TIMESTAMP(s.ts_success_event, 'America/Sao_Paulo') AS ts_first_execution_success_brt,
  cr.ts_last_execution_ended AS ts_last_composer_run,
  FROM_UTC_TIMESTAMP(cr.ts_last_execution_ended, 'America/Sao_Paulo') AS ts_last_composer_run_brt,
  NOW() AS ts_load,
  FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo') AS ts_load_brt
FROM
  datalake_composer_clean.dag_run AS dr
INNER JOIN
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
INNER JOIN
  composer_run AS cr
    ON cr.dt_execution = DATE(dr.ts_ended)
LEFT JOIN
    datalake_gsheets_clean.dags_sla_exclusion_list AS ds
        ON ds.dag = dr.id_dag