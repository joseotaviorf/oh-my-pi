WITH dag_run_base AS (
    SELECT
        dr.id_dag,
        dr.state,
        dr.is_manual_run,
        dr.is_first_run_ever,
        dr.is_triggered_by_mediator,
        dr.is_first_execution_inside_sla,
        ROW_NUMBER() OVER(PARTITION BY id_dag ORDER BY ts_run) AS rn,
        DATE(dr.ts_run) AS dt_run
    FROM
        datalake_pipeline.dag_run AS dr
    WHERE
        DATE(ts_run) = DATE_SUB(MAKE_DATE({year}, {month}, {day}), 1)  -- D-1
),
paused_dates AS (
    SELECT
        id_dag,
        event,
        LEAD(event) OVER(PARTITION BY id_dag ORDER BY ts_event) AS next_event,
        ts_event,
        LEAD(ts_event) OVER(PARTITION BY id_dag ORDER BY ts_event) AS ts_next_event
    FROM
        datalake_composer_clean.log
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
        event = 'paused'
        AND next_event = 'cli_run'
),
dag_base AS (
    SELECT
        d.id_dag,
        d.id_line,
        d.layer,
        d.is_datamart,
        IF(MAKE_DATE({year}, {month}, {day}) BETWEEN pc.ts_event AND pc.ts_next_event, TRUE, FALSE) AS is_paused
    FROM
        datalake_pipeline.dag AS d
    JOIN
        datalake_composer_clean.dag AS dd
            ON dd.id_dag = d.id_dag
    LEFT JOIN
        paused_cli_run AS pc
            ON pc.id_dag = d.id_dag
            AND MAKE_DATE({year}, {month}, {day}) BETWEEN pc.ts_event AND pc.ts_next_event
    WHERE
        MAKE_DATE({year}, {month}, {day}) BETWEEN DATE(d.ts_first_event) AND DATE(dd.ts_last_scheduler_ran) -- Active DAGs only
),
sla_exclusion_list AS (
    SELECT
        dag AS id_dag,
        dt_dag_added,
        dt_dag_removed
    FROM
        datalake_gsheets_clean.dags_sla_exclusion_list
    WHERE
        MAKE_DATE({year}, {month}, {day}) BETWEEN dt_dag_added AND COALESCE(dt_dag_removed, CURRENT_DATE)
),
special_scheduler AS (
    SELECT
        ds.id_dag,
        dr.dt_run,
        ds.dt_added,
        ds.dt_removed
    FROM
        datalake_gsheets_clean.dags_special_scheduler AS ds
    JOIN
        dag_base AS db 
            ON db.id_dag = ds.id_dag    -- Only active DAGs
    LEFT JOIN
        dag_run_base AS dr
            ON dr.id_dag = ds.id_dag
    WHERE
        MAKE_DATE({year}, {month}, {day}) BETWEEN ds.dt_added AND COALESCE(ds.dt_removed, CURRENT_DATE)
),
ignoring_list AS (
    -- Unifying all DAGs that has special scheduler + are in the SLA exclusion list + first execution has null SLA
    SELECT
        id_dag  
    FROM
        special_scheduler
    UNION
    SELECT
        id_dag
    FROM 
        sla_exclusion_list
    UNION
    SELECT
        id_dag
    FROM
        dag_run_base
    WHERE 
        is_first_execution_inside_sla IS NULL
        AND rn = 1 
),
totals_base AS (
    SELECT
        d.id_line,
        COUNT(DISTINCT d.id_dag) AS total_active_dags,
        COUNT(DISTINCT db.id_dag) AS total_dags_executed,
        COUNT(DISTINCT ss.id_dag) AS total_dags_special_scheduler,
        COUNT(DISTINCT ss.id_dag) FILTER (WHERE ss.dt_run IS NOT NULL) total_dags_special_scheduler_executed,
        COUNT(DISTINCT d.id_dag) FILTER (WHERE ds.id_dag IS NOT NULL) AS total_dags_in_sla_exclusion_list,
        COUNT(DISTINCT el.id_dag) AS total_dags_ignoring_list,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE db.is_first_execution_inside_sla = TRUE) AS total_dags_inside_sla,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE db.is_first_execution_inside_sla = FALSE) AS total_dags_outside_sla,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE db.is_first_execution_inside_sla IS NULL) AS total_dags_null_sla,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE db.state = 'success') AS total_success_dags,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE db.state = 'failed') AS total_failed_dags,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE db.is_manual_run = TRUE) AS total_dags_with_manual_run,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE db.is_triggered_by_mediator = TRUE) AS total_dags_triggered_by_mediator,
        COUNT(DISTINCT d.id_dag) FILTER (WHERE d.layer = 'raw/clean') AS total_raw_clean_dags,
        COUNT(DISTINCT d.id_dag) FILTER (WHERE d.layer = 'enrich') AS total_enrich_dags,
        COUNT(DISTINCT d.id_dag) FILTER (WHERE d.layer = 'dw') AS total_dw_dags,
        COUNT(DISTINCT d.id_dag) FILTER (WHERE d.layer = 'metric') AS total_metric_dags,
        COUNT(DISTINCT d.id_dag) FILTER (WHERE d.layer = 'reverse') AS total_reverse_dags,
        COUNT(DISTINCT d.id_dag) FILTER (WHERE d.is_datamart = TRUE) AS total_datamart_dags,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE d.layer = 'raw/clean') AS total_raw_clean_dags_excuted,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE d.layer = 'enrich') AS total_enrich_dags_executed,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE d.layer = 'dw') AS total_dw_dags_executed,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE d.layer = 'metric') AS total_metric_dags_executed,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE d.layer = 'reverse') AS total_reverse_dags_executed,
        COUNT(DISTINCT db.id_dag) FILTER (WHERE d.is_datamart = TRUE) AS total_datamart_dags_executed
    FROM
        dag_base AS d
    LEFT JOIN   -- The DAG run may not exist yet
        dag_run_base AS db
            ON d.id_dag = db.id_dag
    LEFT JOIN
        special_scheduler AS ss
            ON ss.id_dag = d.id_dag
    LEFT JOIN
        ignoring_list AS el
            ON el.id_dag = d.id_dag
    LEFT JOIN
        sla_exclusion_list AS ds
            ON ds.id_dag = d.id_dag
    GROUP BY 1
)
SELECT
    tb.id_line AS sk_line,
    DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS sk_snapshot_date,
    ROUND(100*(tb.total_dags_inside_sla/(tb.total_active_dags - tb.total_dags_ignoring_list + tb.total_dags_special_scheduler_executed)), 1) AS sla,
    tb.total_active_dags,
    tb.total_dags_executed,
    tb.total_dags_special_scheduler,
    tb.total_dags_special_scheduler_executed,
    tb.total_dags_in_sla_exclusion_list,
    tb.total_dags_ignoring_list,
    tb.total_dags_inside_sla,
    tb.total_dags_outside_sla,
    tb.total_dags_null_sla,
    tb.total_success_dags,
    tb.total_failed_dags,
    tb.total_dags_with_manual_run,
    tb.total_dags_triggered_by_mediator,
    tb.total_raw_clean_dags,
    tb.total_raw_clean_dags_excuted,
    tb.total_enrich_dags,
    tb.total_enrich_dags_executed,
    tb.total_dw_dags,
    tb.total_dw_dags_executed,
    tb.total_metric_dags,
    tb.total_metric_dags_executed,
    tb.total_reverse_dags,
    tb.total_reverse_dags_executed,
    tb.total_datamart_dags,
    tb.total_datamart_dags_executed,
    MAKE_DATE({year}, {month}, {day}) AS dt_snapshot,
    NOW() AS ts_load,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    totals_base AS tb