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
    is_manual_run = FALSE   -- Excluding manual DAG runs, because it's created as D0.
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_dag ORDER BY ts_run DESC) = 1
),
medians (
    SELECT
        id_dag,
        MEDIAN(duration) AS median_duration,
        TIMESTAMP(MEDIAN(BIGINT(TIMESTAMP(DATE_FORMAT(ts_started,'HH:mm:ss'))))) AS ts_median_execution_started,
        TIMESTAMP(MEDIAN(BIGINT(TIMESTAMP(DATE_FORMAT(ts_started_brt,'HH:mm:ss'))))) AS ts_median_execution_started_brt,
        TIMESTAMP(MEDIAN(BIGINT(TIMESTAMP(DATE_FORMAT(ts_ended,'HH:mm:ss'))))) AS ts_median_execution_ended,
        TIMESTAMP(MEDIAN(BIGINT(TIMESTAMP(DATE_FORMAT(ts_ended_brt,'HH:mm:ss'))))) AS ts_median_execution_ended_brt
    FROM
        datalake_pipeline.dag_run
    WHERE
        id_run NOT LIKE 'manual%'
    GROUP BY 1
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
        d.layer,
        d.schedule_interval,
        mc.state,
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
),
base AS (
    SELECT
        d.id_dag,
        l.id_line,
        l.line_name,
        d.layer,
        d.schedule_interval,
        s.state,
        ao.number_of_tasks,
        s.duration,
        m.median_duration,
        d.is_active,
        d.is_paused,
        s.is_in_exclusion_list,
        s.is_ignored,
        s.is_inside_sla,
        d.is_datamart,
        IF(DATE(s.ts_last_execution_started) = CURRENT_DATE, TRUE, FALSE) AS has_todays_run_happened,   -- Cases of D0 runs
        fe.ts_first_event,
        FROM_UTC_TIMESTAMP(fe.ts_first_event, 'America/Sao_Paulo') AS ts_first_event_brt,
        s.dt_run AS dt_last_run,
        CASE
            WHEN d.is_datamart = FALSE AND d.layer IN ('raw/clean', 'enrich', 'dw', 'metric') THEN CURRENT_DATE + INTERVAL 11 HOUR -- UTC hour
            WHEN d.is_datamart = TRUE THEN CURRENT_DATE + INTERVAL 13 HOUR
            WHEN d.layer = 'reverse' THEN CURRENT_DATE + INTERVAL 15 HOUR
        END AS ts_utc_sla,
        CASE
            WHEN d.is_datamart = FALSE AND d.layer IN ('raw/clean', 'enrich', 'dw', 'metric') THEN CURRENT_DATE + INTERVAL 8 HOUR -- BRT hour
            WHEN d.is_datamart = TRUE THEN CURRENT_DATE + INTERVAL 10 HOUR
            WHEN d.layer = 'reverse' THEN CURRENT_DATE + INTERVAL 12 HOUR
        END AS ts_brt_sla,
        s.ts_last_execution_started,
        s.ts_last_execution_started_brt,
        m.ts_median_execution_started,
        m.ts_median_execution_started_brt,
        s.ts_last_execution_ended,
        s.ts_last_execution_ended_brt,
        m.ts_median_execution_ended,
        m.ts_median_execution_ended_brt,
        s.ts_last_run_first_success,
        s.ts_last_run_first_success_brt
    FROM
        dag_info AS d
    LEFT JOIN
        sla_base AS s
            ON s.id_dag = d.id_dag
    LEFT JOIN
        first_execution AS fe
            ON fe.id_dag = d.id_dag
    LEFT JOIN
        medians AS m
            ON m.id_dag = d.id_dag
    LEFT JOIN
        amount_of_tasks AS ao
            ON ao.id_dag = d.id_dag
    JOIN
        datalake_pipeline.line AS l
            ON l.line_name = d.line_name
)
SELECT
    b.id_dag,
    id_line,
    line_name,
    layer,
    schedule_interval,
    state,
    HOUR(ts_utc_sla) AS utc_sla_hour,
    HOUR(ts_brt_sla) AS brt_sla_hour,
    number_of_tasks,
    duration,
    median_duration,
    is_active,
    is_paused,
    is_in_exclusion_list,
    is_ignored,
    is_datamart,
    IF(ds.id_dag IS NOT NULL, TRUE, FALSE) AS has_special_scheduler,
    has_todays_run_happened,
    CASE
        WHEN has_todays_run_happened = TRUE AND is_inside_sla = TRUE AND is_ignored = FALSE THEN TRUE
        WHEN has_todays_run_happened = TRUE AND is_inside_sla = FALSE AND is_ignored = FALSE THEN FALSE
        WHEN has_todays_run_happened = FALSE AND is_inside_sla = FALSE AND is_ignored = FALSE AND ds.id_dag IS NULL THEN FALSE
        WHEN has_todays_run_happened = FALSE AND is_ignored = FALSE AND ds.id_dag IS NULL AND NOW() > ts_utc_sla THEN FALSE
        ELSE NULL
    END AS is_inside_sla,
    ts_first_event,
    ts_first_event_brt,
    dt_last_run,
    ts_last_execution_started,
    ts_last_execution_started_brt,
    ts_median_execution_started,
    ts_median_execution_started_brt,
    ts_last_execution_ended,
    ts_last_execution_ended_brt,
    ts_median_execution_ended,
    ts_median_execution_ended_brt,
    ts_last_run_first_success,
    ts_last_run_first_success_brt,
    NOW() AS ts_load,
    FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo') AS ts_load_brt
FROM
    base AS b
LEFT JOIN
    datalake_gsheets_clean.dags_special_scheduler AS ds
        ON ds.id_dag = b.id_dag
        AND CURRENT_DATE BETWEEN dt_added AND COALESCE(dt_removed, CURRENT_DATE)