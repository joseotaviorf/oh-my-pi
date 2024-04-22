WITH most_recent_run AS (
  SELECT
  -- The last run date of a DAG. A reminder that usually our DAGs are D-1.
    id_dag,
    state,
    is_in_exclusion_list,
    is_first_execution_inside_sla AS is_inside_sla,
    DATE(ts_run) AS dt_run
  FROM 
    datalake_pipeline.dag_run
  WHERE
    id_run NOT LIKE 'manual%'   -- Excluding manual DAG runs, because it's created as D0.
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_dag ORDER BY ts_run DESC) = 1
),
most_recent_events AS (
    SELECT
        id_dag,
        duration,
        ts_started AS ts_last_execution_started,
        ts_started_brt AS ts_last_execution_started_brt,
        ts_ended AS ts_last_execution_ended,
        ts_ended_brt AS ts_last_execution_ended_brt,
        ts_first_execution_success AS ts_last_run_first_success,
        ts_first_execution_success_brt AS ts_last_run_first_success_brt
    FROM
        datalake_pipeline.dag_run
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_dag ORDER BY ts_started DESC) = 1
),
first_execution AS (
    SELECT
        id_dag,
        MIN(ts_event) AS ts_first_event
    FROM
        datalake_composer_clean.log
    WHERE
        id_dag LIKE 'bietlejuice%'
    GROUP BY 1
),
base_amount_of_tasks AS (
    -- As some DAGs won't execute all its tasks everyday, like DAGs using short-circuit operators, we're assuming that the last run
    -- that had a cluster/job terminated is the one that we'll use to count the amount of tasks
    SELECT
        id_dag,
        MAX(ts_executed) AS ts_last_run
    FROM
        datalake_composer_clean.log
    WHERE
        id_dag LIKE 'bietlejuice%'
        AND id_task IN ('terminate-cluster', 'job-cluster-finished')
        AND event = 'success'
        AND ts_executed IS NOT NULL
    GROUP BY 1
),
amount_of_tasks AS (
    SELECT
        l.id_dag,
        COUNT(DISTINCT l.id_task) AS number_of_tasks,
        l.ts_executed AS ts_run
    FROM
        datalake_composer_clean.log AS l
    JOIN
        base_amount_of_tasks AS b
            ON b.id_dag = l.id_dag
            AND b.ts_last_run = l.ts_executed
    GROUP BY 1, 3
),
dag_info AS (
    SELECT
        id_dag,
        REPLACE(REPLACE(owners, 'airflow, ', ''), ', airflow', '') AS line_name,
        CASE
            WHEN id_dag LIKE '%.enrich_%' THEN 'enrich'
            WHEN id_dag LIKE '%.dw_%' THEN 'dw'
            WHEN id_dag LIKE '%.metric_%' THEN 'metric'
            WHEN id_dag LIKE '%.reverse_%' THEN 'reverse'
            ELSE 'raw/clean'
        END AS layer,
        schedule_interval,
        is_active,
        is_paused,
        IF(id_dag LIKE '%datamarts%', TRUE, FALSE) AS is_datamart
    FROM
        datalake_composer_clean.dag
    WHERE
        id_dag LIKE 'bietlejuice%'
),
sla_base AS (
    SELECT
        d.id_dag,
        l.id_line,
        d.line_name,
        d.layer,
        d.schedule_interval,
        mc.state,
        CASE
            WHEN d.is_datamart = FALSE AND d.layer IN ('raw/clean', 'enrich', 'dw', 'metric') THEN 11 -- UTC hour
            WHEN d.is_datamart = TRUE THEN 13
            WHEN d.layer = 'reverse' THEN 15
        END AS utc_sla_hour,
        me.duration,
        d.is_active,
        d.is_paused,
        mc.is_in_exclusion_list,
        IF(d.is_active = FALSE OR d.is_paused = TRUE OR mc.is_in_exclusion_list = TRUE, TRUE, FALSE) AS is_ignored,
        d.is_datamart,
        mc.is_inside_sla,
        mc.dt_run,
        me.ts_last_execution_started,
        me.ts_last_execution_started_brt,
        me.ts_last_execution_ended,
        me.ts_last_execution_ended_brt,
        me.ts_last_run_first_success,
        me.ts_last_run_first_success_brt
    FROM
        dag_info AS d
    JOIN
        most_recent_run AS mc
            ON mc.id_dag = d.id_dag
    JOIN
        most_recent_events AS me
            ON me.id_dag = d.id_dag
    JOIN
        datalake_pipeline.line AS l
            ON l.line_name = d.line_name
)
SELECT
    s.id_dag,
    s.id_line,
    s.line_name,
    s.layer,
    s.schedule_interval,
    s.state,
    s.utc_sla_hour,
    CASE
        WHEN s.utc_sla_hour = 11 THEN 8
        WHEN s.utc_sla_hour = 13 THEN 10
        WHEN s.utc_sla_hour = 15 THEN 12
        ELSE NULL
    END AS brt_sla_hour,
    ao.number_of_tasks,
    s.duration,
    s.is_active,
    s.is_paused,
    s.is_in_exclusion_list,
    IF(s.is_ignored = TRUE, NULL, s.is_inside_sla) AS is_inside_sla,
    s.is_datamart,
    IF(DATE(s.ts_last_execution_started) = CURRENT_DATE, TRUE, FALSE) AS has_todays_run_happened,   -- Cases of D0 runs
    fe.ts_first_event,
    FROM_UTC_TIMESTAMP(fe.ts_first_event, 'America/Sao_Paulo') AS ts_first_event_brt,
    s.dt_run AS dt_last_run,
    s.ts_last_execution_started,
    s.ts_last_execution_started_brt,
    s.ts_last_execution_ended,
    s.ts_last_execution_ended_brt,
    s.ts_last_run_first_success,
    s.ts_last_run_first_success_brt,
    NOW() AS ts_load,
    FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo') AS ts_load_brt
FROM
    sla_base AS s
JOIN
    first_execution AS fe
        ON fe.id_dag = s.id_dag
LEFT JOIN
    amount_of_tasks AS ao
        ON ao.id_dag = s.id_dag