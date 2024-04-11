WITH most_recent_run AS (
    SELECT
        id_dag,
        state,
        is_in_exclusion_list,
        is_first_execution_inside_sla AS is_inside_sla,
        DATE(ts_execution) AS dt_execution,
        ts_started AS ts_last_run_started,
        ts_started_brt AS ts_last_run_started_brt,
        ts_ended AS ts_last_run_ended,
        ts_ended_brt AS ts_last_run_ended_brt,
        ts_first_execution_success AS ts_last_run_first_success,
        ts_first_execution_success_brt AS ts_last_run_first_success_brt
    FROM
        datalake_pipeline.dag_run
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_dag ORDER BY ts_execution DESC) = 1
),
base_amount_of_tasks AS (
    -- As some DAGs won't execute all its tasks everyday, like DAGs using short-circuit operators, we're assuming that the last run
    -- that had a cluster/job terminated is the one that we'll use to count the amount of tasks
    SELECT
        id_dag,
        MAX(ts_executed) AS ts_last_execution
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
        l.ts_executed
    FROM
        datalake_composer_clean.log AS l
    JOIN
        base_amount_of_tasks AS b
            ON b.id_dag = l.id_dag
            AND b.ts_last_execution = l.ts_executed
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
            ELSE NULL   -- Reverse layer doesn't have a SLA
        END AS utc_sla_hour,
        d.is_active,
        d.is_paused,
        mc.is_in_exclusion_list,
        d.is_datamart,
        mc.is_inside_sla,
        mc.dt_execution,
        mc.ts_last_run_started,
        mc.ts_last_run_started_brt,
        mc.ts_last_run_ended,
        mc.ts_last_run_ended_brt,
        mc.ts_last_run_first_success,
        mc.ts_last_run_first_success_brt
    FROM
        dag_info AS d
    JOIN
        most_recent_run AS mc
            ON mc.id_dag = d.id_dag
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
        ELSE NULL
    END AS brt_sla_hour,
    ao.number_of_tasks,
    s.is_active,
    s.is_paused,
    s.is_in_exclusion_list,
    s.is_inside_sla,
    s.is_datamart,
    IF(DATE(s.ts_last_run_started) = CURRENT_DATE, TRUE, FALSE) AS has_todays_run_happened,   -- Cases of D0 runs
    s.dt_execution AS dt_last_execution,
    s.ts_last_run_started,
    s.ts_last_run_started_brt,
    s.ts_last_run_ended,
    s.ts_last_run_ended_brt,
    s.ts_last_run_first_success,
    s.ts_last_run_first_success_brt,
    NOW() AS ts_load,
    FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo') AS ts_load_brt
FROM
    sla_base AS s
LEFT JOIN
    amount_of_tasks AS ao
        ON ao.id_dag = s.id_dag