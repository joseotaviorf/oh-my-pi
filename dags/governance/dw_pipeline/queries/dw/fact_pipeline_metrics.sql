WITH totals_base AS (
    SELECT
        ds.id_line,
        COUNT(DISTINCT ds.id_dag) AS total_active_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_active_and_unpaused = TRUE) AS total_active_unpaused_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_executed = TRUE) AS total_dags_executed,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_special_scheduler = TRUE) AS total_dags_special_scheduler,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_special_scheduler_executed = TRUE) AS total_dags_special_scheduler_executed,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_in_sla_exclusion_list = TRUE) AS total_dags_in_sla_exclusion_list,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_in_ignoring_list = TRUE) AS total_dags_ignoring_list,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_inside_sla = TRUE) AS total_dags_inside_sla,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_outside_sla = TRUE) AS total_dags_outside_sla,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_null_sla = TRUE) AS total_dags_null_sla,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_run_successful = TRUE) AS total_success_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_run_failed = TRUE) AS total_failed_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_manual_run = TRUE) AS total_dags_with_manual_run,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE ds.is_run_triggered_by_mediator = TRUE) AS total_dags_triggered_by_mediator,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'raw/clean') AS total_raw_clean_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'enrich') AS total_enrich_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'dw') AS total_dw_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'metric') AS total_metric_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'reverse') AS total_reverse_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.is_datamart = TRUE) AS total_datamart_dags,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'raw/clean' AND ds.is_executed = TRUE) AS total_raw_clean_dags_excuted,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'enrich' AND ds.is_executed = TRUE) AS total_enrich_dags_executed,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'dw' AND ds.is_executed = TRUE) AS total_dw_dags_executed,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'metric' AND ds.is_executed = TRUE) AS total_metric_dags_executed,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.layer = 'reverse' AND ds.is_executed = TRUE) AS total_reverse_dags_executed,
        COUNT(DISTINCT ds.id_dag) FILTER (WHERE d.is_datamart = TRUE AND ds.is_executed = TRUE) AS total_datamart_dags_executed,
        ds.dt_snapshot
    FROM
        datalake_pipeline.dag_sla_information AS ds
    JOIN
        datalake_pipeline.dag AS d
            ON d.id_dag = ds.id_dag
    WHERE
        ds.dt_snapshot BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY 1, 28
)
SELECT
    tb.id_line AS sk_line,
    DATE_FORMAT(tb.dt_snapshot, 'yyyyMMdd') AS sk_snapshot_date,
    ROUND(100*(tb.total_dags_inside_sla/(tb.total_active_unpaused_dags - tb.total_dags_ignoring_list + tb.total_dags_special_scheduler_executed)), 1) AS sla,
    tb.total_active_dags,
    tb.total_active_unpaused_dags,
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
    tb.dt_snapshot,
    NOW() AS ts_load,
    YEAR(tb.dt_snapshot) AS year,
    MONTH(tb.dt_snapshot) AS month,
    DAY(tb.dt_snapshot) AS day
FROM
    totals_base AS tb