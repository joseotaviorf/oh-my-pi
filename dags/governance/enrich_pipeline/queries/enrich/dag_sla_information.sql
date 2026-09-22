WITH load_dates AS (
    SELECT
        date
    FROM
        datalake_quintoandar.aux_date
    WHERE
        date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
intraday_dags_ranked AS (
    SELECT
        id_dag,
        schedule_interval,
        CASE
            WHEN schedule_interval IS NULL OR schedule_interval = '' THEN FALSE
            WHEN schedule_interval LIKE "%@hourly%" THEN TRUE
            -- check for intraday cron expressions
            WHEN SPLIT(schedule_interval, ' ')[1] = '*' THEN TRUE
            WHEN CONTAINS(SPLIT(schedule_interval, ' ')[1], ',') THEN TRUE
            WHEN CONTAINS(SPLIT(schedule_interval, ' ')[1], '-') THEN TRUE
            WHEN CONTAINS(SPLIT(schedule_interval, ' ')[1], '/') THEN TRUE
            WHEN SPLIT(schedule_interval, ' ')[0] = '*' THEN TRUE
            WHEN CONTAINS(SPLIT(schedule_interval, ' ')[0], ',') THEN TRUE
            WHEN CONTAINS(SPLIT(schedule_interval, ' ')[0], '-') THEN TRUE
            WHEN CONTAINS(SPLIT(schedule_interval, ' ')[0], '/') THEN TRUE
            ELSE FALSE
        END AS is_intraday,
        ROW_NUMBER() OVER(PARTITION BY id_dag ORDER BY ts_last_parsed DESC) AS rn
    FROM
        datalake_astro_clean.dag
),
intraday_dags AS (
    -- get the most recent schedule interval for each DAG
    SELECT
        id_dag,
        schedule_interval,
        is_intraday
    FROM
        intraday_dags_ranked
    WHERE
        rn = 1
),
dag_run_base AS (
    SELECT
        dr.id_dag,
        dr.state,
        dr.is_manual_run,
        dr.is_first_run_ever,
        dr.is_triggered_by_mediator,
        dr.is_first_execution_inside_sla,
        ROW_NUMBER() OVER(PARTITION BY id_dag, DATE(dr.ts_data_interval_started) ORDER BY ts_data_interval_started) AS rn,
        DATE(dr.ts_data_interval_started) AS dt_run,
        DATE_ADD(dr.ts_data_interval_started, 1) AS dt_event,
        ts_first_execution_success,
        ts_first_execution_success_brt,
        ts_last_table_task_successful,
        ts_last_table_task_successful_brt
    FROM
        datalake_pipeline.dag_run AS dr
    WHERE
        DATE(ts_data_interval_started) BETWEEN DATE_SUB(DATE('{load_start_date}'), 1) AND DATE_SUB(DATE('{load_end_date}'), 1) -- Runs are D-1
),
paused_dates AS (
    SELECT
        id_dag,
        ts_event,
        CASE
            -- astro semantics: event is always 'paused' and the real status comes in the payload.
            -- TODO: verify column type before EMR migration; default rewrite is GET_JSON_OBJECT if STRING JSON
            WHEN event = 'paused' THEN CAST(GET_JSON_OBJECT(extra, '$.is_paused') AS BOOLEAN)
            -- legacy semantics: 'paused' means paused, 'cli_run' means active/unpaused.
            WHEN event = 'cli_run' THEN FALSE
            ELSE NULL
        END AS is_paused_status
    FROM
        datalake_airflow.log
    WHERE
        event IN ('paused', 'cli_run')
        AND id_dag LIKE 'bietlejuice%'
),
paused_cli_run AS (
    SELECT
        id_dag,
        ts_event,
        ts_next_event
    FROM (
        SELECT
            id_dag,
            ts_event,
            is_paused_status,
            LAG(is_paused_status) OVER (PARTITION BY id_dag ORDER BY ts_event) AS prev_is_paused_status,
            LEAD(ts_event) OVER (PARTITION BY id_dag ORDER BY ts_event) AS ts_next_event
        FROM
            paused_dates
        WHERE
            is_paused_status IS NOT NULL
    )
    WHERE
        is_paused_status = TRUE
        AND (prev_is_paused_status IS NULL OR prev_is_paused_status <> is_paused_status)
),
astro_dag_pause_status_ranked AS (
    SELECT
        id_dag,
        MAKE_DATE(year, month, day) AS dt_event,
        is_paused,
        ROW_NUMBER() OVER (
            PARTITION BY id_dag, MAKE_DATE(year, month, day)
            ORDER BY ts_last_parsed DESC
        ) AS rn
    FROM
        datalake_astro_clean.dag
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
astro_dag_pause_status AS (
    SELECT
        id_dag,
        dt_event,
        is_paused
    FROM
        astro_dag_pause_status_ranked
    WHERE
        rn = 1
),
dag_base AS (
    SELECT
        d.id_dag,
        d.id_line,
        d.layer,
        d.criticality,
        d.sla_deadline_localtime,
        d.is_datamart,
        COALESCE(
            ads.is_paused,
            IF(ad.date BETWEEN DATE(pc.ts_event) AND COALESCE(DATE(pc.ts_next_event), CURRENT_DATE), TRUE, FALSE)
        ) AS is_paused,
        ad.date AS dt_event
    FROM
        datalake_pipeline.dag AS d
    JOIN
        datalake_airflow.dag AS dd
            ON dd.id_dag = d.id_dag
    CROSS JOIN
        load_dates AS ad
    LEFT JOIN
        astro_dag_pause_status AS ads
            ON ads.id_dag = d.id_dag
            AND ads.dt_event = ad.date
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
    CROSS JOIN
        load_dates AS ad
    WHERE
        ad.date BETWEEN dt_dag_added AND COALESCE(dt_dag_removed, CURRENT_DATE)
    UNION
    -- Shadow/validation DAGs (cluster.validation): manual-only, never in Data SLA
    SELECT
        id_dag,
        dt_event
    FROM
        dag_base
    WHERE
        endswith(id_dag, '__validation')
),
special_scheduler AS (
    SELECT
        ds.id_dag,
        dr.dt_run,
        ad.date AS dt_event
    FROM
        datalake_gsheets_clean.dags_special_scheduler AS ds
    CROSS JOIN
        load_dates AS ad
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
        d.criticality,
        d.sla_deadline_localtime,
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
            WHEN ss.id_dag IS NOT NULL
                AND db.id_dag IS NOT NULL
                AND COALESCE(db.is_manual_run, FALSE) = FALSE
                AND COALESCE(db.is_first_run_ever, FALSE) = FALSE
                THEN TRUE
            WHEN ss.id_dag IS NOT NULL THEN FALSE
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
            WHEN d.sla_deadline_localtime IS NULL OR d.is_paused = TRUE THEN NULL
            WHEN db.ts_last_table_task_successful_brt IS NOT NULL
                AND db.ts_last_table_task_successful_brt
                    <= CAST(CONCAT(CAST(d.dt_event AS STRING), ' ', d.sla_deadline_localtime, ':00') AS TIMESTAMP) THEN TRUE
            WHEN db.ts_last_table_task_successful_brt IS NOT NULL THEN FALSE
            -- deadline not reached yet on the snapshot day: undecided, not a miss
            WHEN FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo')
                    <= CAST(CONCAT(CAST(d.dt_event AS STRING), ' ', d.sla_deadline_localtime, ':00') AS TIMESTAMP) THEN NULL
            ELSE FALSE
        END AS is_inside_declared_sla,
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
        id.is_intraday AS is_intraday_dag,
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
    LEFT JOIN
        intraday_dags AS id
            ON id.id_dag = d.id_dag
)
SELECT
    id_dag,
    id_line,
    criticality,
    sla_deadline_localtime,
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
    is_inside_declared_sla,
    is_run_successful,
    is_run_failed,
    is_manual_run,
    is_run_triggered_by_mediator,
    is_intraday_dag,
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
