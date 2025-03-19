WITH first_run_ever AS (
  -- The first run of a DAG shouldn't be considered to calculate our SLA, so it's important to mark it
  SELECT
    id_dag,
    ts_executed
  FROM
    datalake_airflow.log
  WHERE
    id_dag LIKE 'bietlejuice%'
    AND (id_task IN ('create-cluster', 'execute-job-cluster')
      OR id_task LIKE '%-skip-execution%')  -- Some DAGs may have as the first task a short-circuit that skips the cluster/job creation
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_dag ORDER BY ts_event ASC) = 1
),
/** 
  Using DAG Inventory, we can related the id_task with the table. Usually we use the cluster termination task to understand if a DAG was
  inside or outside the SLA, but in Q3 and Q4/2023, we wrongly removed this task and we ended up with a gap in our SLA.
  In order to "fix" it, we're using the id_task timestamp of success to understand if the DAG was inside or outside the SLA. 
  If by some reason we don't have information related to the task (some error with DAG Inventory, for example), we'll be considering
  the cluster termination successful timestamp.
**/
dag_inventory AS (
  SELECT
    dag AS id_dag,
    task AS id_task,
    layer,
    MAKE_DATE(year, month, day) AS dt_extracted,
    DATE_ADD(MAKE_DATE(year, month, day), 1) AS dt_current
  FROM
    datalake_dag_inventory_clean.table
  WHERE
    dag LIKE 'bietlejuice%'
),
first_task_success_log AS (
  -- Checking the first time that the DAG run was marked as successful, based on the table tasks
  SELECT
    id_dag,
    id_task,
    TIMESTAMP(ts_event) AS ts_success_event,
    DATE(ts_executed) AS dt_run
  FROM
    datalake_airflow.log
  WHERE
    id_dag LIKE 'bietlejuice%'
    AND event = 'success'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_dag, id_task, DATE(ts_executed) ORDER BY ts_event ASC) = 1
),
table_task_success AS (
  SELECT
    l.id_dag,
    l.id_task,
    di.layer,
    dt_run,
    dt_extracted,
    ts_success_event,
    CASE
      WHEN layer = 'reverse' THEN COALESCE(DATE(ts_success_event), DATE_ADD(dt_run, 1)) + INTERVAL 15 HOUR
      WHEN l.id_dag LIKE '%datamart%' OR layer = 'metric' THEN COALESCE(DATE(ts_success_event), DATE_ADD(dt_run, 1)) + INTERVAL 13 HOUR
      ELSE COALESCE(DATE(ts_success_event), DATE_ADD(dt_run, 1)) + INTERVAL 11 HOUR
    END AS ts_expected_sla
  FROM
    first_task_success_log AS l
  LEFT JOIN -- Left because we need to consider dummy tasks
    dag_inventory AS di
      ON l.id_task = di.id_task
      AND l.dt_run = di.dt_extracted
  WHERE
    di.id_task IS NOT NULL  -- Assuring that we're only having the task that loads a table or dummy tasks
    OR l.id_task LIKE '%-skip-execution%'
    OR l.id_task LIKE 'done-clean%'
),
expected_task_sla AS (
  -- Checking if the task tables of a DAG are inside the expected SLA
  SELECT
    id_dag,
    id_task,
    IF(ts_success_event IS NULL OR ts_success_event > ts_expected_sla, FALSE, TRUE) AS is_inside_sla,
    dt_run,
    ts_success_event,
    ts_expected_sla
  FROM
    table_task_success AS tts 
),
expected_tasks AS (
  SELECT
    es.id_dag,
    dt_run,
    COUNT(DISTINCT es.id_task) AS tables,
    COUNT(DISTINCT es.id_task) FILTER (WHERE is_inside_sla = TRUE) AS tables_inside_sla,
    COUNT(DISTINCT es.id_task) FILTER (WHERE is_inside_sla = FALSE) AS tables_outside_sla,
    MAX(es.ts_success_event) AS ts_last_task_successful
  FROM
    expected_task_sla AS es
  GROUP BY 1, 2
),
all_tasks_sla AS (
  SELECT
    id_dag,
    IF(tables = tables_inside_sla, TRUE, FALSE) AS is_all_tables_inside_sla,
    dt_run,
    ts_last_task_successful
  FROM
    expected_tasks
),
success_run AS (
  -- Checking the first time that the DAG run was marked as successful, based on the job/cluster termination task
  SELECT
    l.id_dag,
    TIMESTAMP(l.ts_executed) AS ts_executed,
    l.ts_event AS ts_success_event,
    CASE
        WHEN layer = 'reverse' THEN COALESCE(DATE(l.ts_event), DATE_ADD(l.ts_executed, 1)) + INTERVAL 15 HOUR
        WHEN di.id_dag LIKE '%datamart%' OR layer = 'metric' THEN COALESCE(DATE(l.ts_event), DATE_ADD(l.ts_executed, 1)) + INTERVAL 13 HOUR
        ELSE COALESCE(DATE(l.ts_event), DATE_ADD(l.ts_executed, 1)) + INTERVAL 11 HOUR
      END AS ts_expected_sla
  FROM
    datalake_airflow.log AS l
  LEFT JOIN -- We have cases where DAG Inventory was broken and didn't run
    dag_inventory AS di
      ON di.id_dag = l.id_dag
      AND di.dt_extracted = DATE(l.ts_executed)
  JOIN
    datalake_airflow.dag_run AS dr
      ON dr.id_dag = l.id_dag
      AND dr.ts_executed = l.ts_executed
      AND dr.id_run NOT LIKE 'manual%'  -- Excluding manual runs, which we're not considering on the SLA
  WHERE
    l.id_dag LIKE 'bietlejuice%'
    AND event = 'success'
    AND (l.id_task IN ('terminate-cluster', 'job-cluster-finished')
      OR l.id_task LIKE '%-skip-execution%') -- Some DAGs may have as the first task a short-circuit that skips the cluster/job creation
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY l.id_dag, DATE(l.ts_executed) ORDER BY l.ts_event ASC) = 1
),
dag_clear AS (
  -- Checking if the DAG run suffered any clear, which indicates that it ran more than once
  SELECT DISTINCT
    id_dag,
    ts_executed
  FROM
    datalake_airflow.log
  WHERE
    id_dag LIKE 'bietlejuice%'
    AND event IN ('clear', 'dagrun_clear')
),
composer_run AS (
  /** Finding the most recent run of the Airflow ingestion DAG for each execution date.
    The Airflow ingestion DAG used to be bietlejuice.composer, but it's now been bietlejuice.astro since March 2025.
    It is a DAG that runs D0 and several times a day, which means that if today is 2024-04-10, the execution date will also be 2024-04-10.
    On the next day (2024-04-11) in its first extraction, it will extract the data related to the end of the day of the 2024-04-10.
    So in this case, the execution date 2024-04-10 will have as it last run marked as the date of 2024-04-11
  ***/ 
  SELECT
    DATE(ts_executed) AS dt_execution,
    MAX(ts_started) AS ts_last_execution_started,
    MAX(ts_ended) AS ts_last_execution_ended
  FROM
    datalake_airflow.dag_run
  WHERE
    id_dag IN ('bietlejuice.composer', 'bietlejuice.astro')
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
    WHEN fre.id_dag IS NOT NULL OR ds.dag IS NOT NULL OR dr.id_run LIKE 'manual%' THEN NULL -- Excluding DAGs on the SLA exclusion list
    WHEN s.ts_success_event <= s.ts_expected_sla THEN TRUE 
    WHEN s.ts_success_event > s.ts_expected_sla AND is_all_tables_inside_sla <> TRUE THEN FALSE
    WHEN s.ts_success_event > s.ts_expected_sla AND is_all_tables_inside_sla = TRUE THEN TRUE
    WHEN s.ts_success_event IS NULL THEN is_all_tables_inside_sla
    ELSE NULL
  END AS is_first_execution_inside_sla,
  IF(c.id_dag IS NOT NULL, TRUE, FALSE) AS has_been_cleared,
  dr.ts_executed AS ts_run,
  FROM_UTC_TIMESTAMP(dr.ts_executed, 'America/Sao_Paulo') AS ts_run_brt,
  dr.ts_started,
  FROM_UTC_TIMESTAMP(dr.ts_started, 'America/Sao_Paulo') AS ts_started_brt,
  dr.ts_ended,
  FROM_UTC_TIMESTAMP(dr.ts_ended, 'America/Sao_Paulo') AS ts_ended_brt,
  TIMESTAMP(s.ts_success_event) AS ts_first_execution_success,
  FROM_UTC_TIMESTAMP(s.ts_success_event, 'America/Sao_Paulo') AS ts_first_execution_success_brt,
  IF(et.is_all_tables_inside_sla = TRUE, et.ts_last_task_successful, NULL) AS ts_last_table_task_successful,
  IF(et.is_all_tables_inside_sla = TRUE, FROM_UTC_TIMESTAMP(et.ts_last_task_successful, 'America/Sao_Paulo'), NULL) AS ts_last_table_task_successful_brt,
  cr.ts_last_execution_ended AS ts_last_composer_run,
  FROM_UTC_TIMESTAMP(cr.ts_last_execution_ended, 'America/Sao_Paulo') AS ts_last_composer_run_brt,
  NOW() AS ts_load,
  FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo') AS ts_load_brt
FROM
  datalake_airflow.dag_run AS dr
INNER JOIN
  datalake_airflow.dag AS d
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
  all_tasks_sla AS et
    ON et.id_dag = dr.id_dag
    AND et.dt_run = DATE(dr.ts_executed)
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
        AND DATE(dr.ts_executed)
          BETWEEN IF(ds.is_d0 = FALSE, DATE_ADD(ds.dt_dag_added, -1), ds.dt_dag_added)  -- Runs usually are D-1
            AND IF(ds.is_d0 = FALSE, DATE_ADD(COALESCE(ds.dt_dag_removed, CURRENT_DATE), -1), COALESCE(ds.dt_dag_removed, CURRENT_DATE)) 