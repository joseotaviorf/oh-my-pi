WITH dag_run_base AS (
    SELECT
        dr.id_dag,
        dr.state,
        dr.is_manual_run,
        dr.is_first_run_ever,
        dr.is_triggered_by_mediator,
        dr.is_first_execution_inside_sla,
        ROW_NUMBER() OVER(PARTITION BY id_dag, DATE(dr.ts_run) ORDER BY ts_run) AS rn,
        DATE(dr.ts_run) AS dt_run,
        DATE_ADD(dr.ts_run, 1) AS dt_event,
        ts_first_execution_success,
        ts_first_execution_success_brt,
        ts_last_table_task_successful,
        ts_last_table_task_successful_brt
    FROM
        datalake_pipeline.dag_run AS dr
    WHERE
        DATE(ts_run) BETWEEN DATE_SUB(DATE('{load_start_date}'), 1) AND DATE_SUB(DATE('{load_end_date}'), 1) -- Runs are D-1
),
paused_dates AS (
    SELECT
        id_dag,
        event,
        LEAD(event) OVER(PARTITION BY id_dag ORDER BY ts_event) AS next_event,
        ts_event,
        LEAD(ts_event) OVER(PARTITION BY id_dag ORDER BY ts_event) AS ts_next_event
    FROM
        datalake_airflow.log
    WHERE
        event IN ('paused', 'cli_run')
        AND id_dag LIKE 'bietlejuice%'
),
paused_cli_run AS (
    SELECT
        id_dag,
        event,
        next_event,
        ts_event,
        ts_next_event
    FROM
        paused_dates
    WHERE
        (event = 'paused' AND next_event IS NULL)   -- The DAG is currently paused and hasn't had any event since then
        OR (event = 'paused' AND next_event = 'cli_run')    -- The DAG was paused for a period but had another active event
        OR (event = 'cli_run' AND next_event = 'paused')    -- The DAG was active but was paused
),
dag_base AS (
    SELECT
        d.id_dag,
        d.id_line,
        d.layer,
        d.is_datamart,
        IF(ad.date BETWEEN DATE(pc.ts_event) AND COALESCE(DATE(pc.ts_next_event), CURRENT_DATE), TRUE, FALSE) AS is_paused,
        ad.date AS dt_event
    FROM
        datalake_pipeline.dag AS d
    JOIN
        datalake_airflow.dag AS dd
            ON dd.id_dag = d.id_dag
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    LEFT JOIN
        paused_cli_run AS pc
            ON pc.id_dag = d.id_dag
            AND ad.date BETWEEN DATE(pc.ts_event) AND COALESCE(DATE(pc.ts_next_event), CURRENT_DATE)
    WHERE
        ad.date BETWEEN DATE(d.ts_first_event) AND DATE(dd.ts_last_scheduler_ran) -- Active DAGs only
),
sla_exclusion_list AS (
    SELECT
        dag AS id_dag,
        ad.date AS dt_event
    FROM
        datalake_gsheets_clean.dags_sla_exclusion_list AS g
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    WHERE
        ad.date BETWEEN dt_dag_added AND COALESCE(dt_dag_removed, CURRENT_DATE)
),
special_scheduler AS (
    SELECT
        ds.id_dag,
        dr.dt_run,
        ad.date AS dt_event
    FROM
        datalake_gsheets_clean.dags_special_scheduler AS ds
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    JOIN
        dag_base AS db 
            ON db.id_dag = ds.id_dag    -- Only active DAGs
            AND db.dt_event = ad.date
    LEFT JOIN
        dag_run_base AS dr
            ON dr.id_dag = ds.id_dag
            AND dr.dt_event = ad.date
    WHERE
        ad.date BETWEEN ds.dt_added AND COALESCE(ds.dt_removed, CURRENT_DATE)
),
ignoring_list AS (
    -- Unifying all DAGs that has special scheduler + are in the SLA exclusion list + first execution has null SLA
    SELECT
        id_dag,
        dt_event 
    FROM
        special_scheduler 
    -- Adding DAGs with special scheduler that executed or not, since the ones that executed soon will be removed
    UNION
    SELECT
        id_dag,
        dt_event
    FROM 
        sla_exclusion_list
    UNION
    SELECT
        id_dag,
        dt_event
    FROM
        dag_run_base
    WHERE 
        rn = 1 
        AND is_first_execution_inside_sla IS NULL
),
checking_ignored_tables AS (
    -- Assuring that the DAGs to be ignored are currently active and running on Airflow, 
    -- otherwise we could be counting on the calculation DAGs that doesn't exist anymore
    SELECT
        i.id_dag,
        i.dt_event
    FROM
        ignoring_list AS i
    JOIN
        dag_base AS d
            ON d.id_dag = i.id_dag
            AND d.dt_event = i.dt_event
            AND d.is_paused = FALSE
),
base AS (
    SELECT DISTINCT
        d.id_dag,
        d.id_line,
        TRUE AS is_active,
        CASE
            WHEN d.is_paused = FALSE THEN TRUE
            WHEN d.is_paused = TRUE THEN FALSE 
            ELSE NULL
        END AS is_active_and_unpaused,
        CASE
            WHEN db.id_dag IS NOT NULL THEN TRUE
            WHEN db.id_dag IS NULL THEN FALSE
            ELSE NULL
        END AS is_executed,
        CASE
            WHEN ss.id_dag IS NOT NULL THEN TRUE
            WHEN ss.id_dag IS NULL THEN FALSE
            ELSE NULL
        END AS is_special_scheduler,
        CASE
            WHEN ss.id_dag IS NOT NULL AND ss.dt_run IS NOT NULL THEN TRUE
            WHEN ss.id_dag IS NOT NULL AND ss.dt_run IS NULL THEN FALSE
            ELSE NULL
        END AS is_special_scheduler_executed,
        CASE
            WHEN ds.id_dag IS NOT NULL THEN TRUE 
            WHEN ds.id_dag IS NULL THEN FALSE
            ELSE NULL
        END AS is_in_sla_exclusion_list,
        CASE
            WHEN c.id_dag IS NOT NULL THEN TRUE
            WHEN c.id_dag IS NULL THEN FALSE
            ELSE NULL
        END AS is_in_ignoring_list,
        CASE
            WHEN d.is_paused = FALSE AND db.id_dag IS NOT NULL AND db.is_first_execution_inside_sla = TRUE THEN TRUE
            WHEN d.is_paused = FALSE AND db.id_dag IS NOT NULL AND db.is_first_execution_inside_sla = FALSE THEN FALSE
            ELSE NULL 
        END AS is_inside_sla,
        CASE
            WHEN d.is_paused = FALSE AND db.id_dag IS NOT NULL AND db.is_first_execution_inside_sla = FALSE THEN TRUE
            WHEN d.is_paused = FALSE AND db.id_dag IS NOT NULL AND db.is_first_execution_inside_sla = TRUE THEN FALSE
            ELSE NULL
        END AS is_outside_sla,
        CASE
            WHEN (d.is_paused = FALSE AND db.id_dag IS NOT NULL AND db.is_first_execution_inside_sla IS NULL) OR c.id_dag IS NOT NULL THEN TRUE
            WHEN (d.is_paused = FALSE AND db.id_dag IS NOT NULL AND db.is_first_execution_inside_sla IS NOT NULL) OR c.id_dag IS NULL THEN FALSE
            ELSE NULL
        END AS is_null_sla,
        CASE
            WHEN db.id_dag IS NOT NULL AND db.state = 'success' THEN TRUE 
            WHEN db.id_dag IS NOT NULL AND db.state <> 'success' THEN FALSE
            ELSE NULL
        END AS is_run_successful,
        CASE
            WHEN db.id_dag IS NOT NULL AND db.state = 'failed' THEN TRUE 
            WHEN db.id_dag IS NOT NULL AND db.state <> 'failed' THEN FALSE
            ELSE NULL
        END AS is_run_failed,
        CASE
            WHEN db.id_dag IS NOT NULL AND db.is_manual_run = TRUE THEN TRUE 
            WHEN db.id_dag IS NOT NULL AND db.is_manual_run <> TRUE THEN FALSE
            ELSE NULL
        END AS is_manual_run,
        CASE
            WHEN db.id_dag IS NOT NULL AND db.is_triggered_by_mediator = TRUE THEN TRUE 
            WHEN db.id_dag IS NOT NULL AND db.is_triggered_by_mediator <> TRUE THEN FALSE
            ELSE NULL
        END AS is_run_triggered_by_mediator,
        d.dt_event,
        db.dt_run,
        db.ts_first_execution_success,
        db.ts_first_execution_success_brt,
        db.ts_last_table_task_successful,
        db.ts_last_table_task_successful_brt
    FROM
        dag_base AS d
    LEFT JOIN   -- The DAG run may not exist yet
        dag_run_base AS db
            ON d.id_dag = db.id_dag
            AND d.dt_event = db.dt_event
    LEFT JOIN
        special_scheduler AS ss
            ON ss.id_dag = d.id_dag
            AND ss.dt_event = d.dt_event
    LEFT JOIN
        checking_ignored_tables AS c
            ON c.id_dag = d.id_dag
            AND c.dt_event = d.dt_event
    LEFT JOIN
        sla_exclusion_list AS ds
            ON ds.id_dag = d.id_dag
            AND ds.dt_event = d.dt_event
)
SELECT
    id_dag,
    id_line,
    is_active,
    is_active_and_unpaused,
    is_executed,
    is_special_scheduler,
    is_special_scheduler_executed,
    is_in_sla_exclusion_list,
    is_in_ignoring_list,
    is_inside_sla,
    is_outside_sla,
    is_null_sla,
    is_run_successful,
    is_run_failed,
    is_manual_run,
    is_run_triggered_by_mediator,
    CASE
        WHEN is_active_and_unpaused = TRUE AND COALESCE(is_inside_sla, is_outside_sla, is_null_sla) IS NULL THEN TRUE
        WHEN is_active_and_unpaused = TRUE AND is_in_ignoring_list = FALSE AND COALESCE(is_inside_sla, is_outside_sla) IS NULL THEN TRUE
        WHEN is_active_and_unpaused = TRUE AND is_special_scheduler_executed = TRUE AND is_in_sla_exclusion_list = FALSE 
         AND COALESCE(is_inside_sla, is_outside_sla) IS NULL AND is_null_sla = TRUE THEN TRUE
        WHEN is_active_and_unpaused = TRUE AND is_special_scheduler_executed = TRUE AND is_in_ignoring_list = FALSE THEN TRUE
        ELSE NULL  
    END AS has_possible_problem,
    dt_event AS dt_snapshot,
    dt_run,
    ts_first_execution_success,
    ts_first_execution_success_brt,
    ts_last_table_task_successful,
    ts_last_table_task_successful_brt,
    YEAR(dt_event) AS year,
    MONTH(dt_event) AS month,
    DAY(dt_event) AS day
FROM
    base 