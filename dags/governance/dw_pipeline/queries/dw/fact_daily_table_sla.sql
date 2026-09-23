SELECT
    ts.id_table AS sk_table,
    ts.id_dag AS sk_dag,
    MAX(ts.id_line) AS sk_line,
    BIGINT(DATE_FORMAT(ts.dt_snapshot, 'yyyyMMdd')) AS sk_snapshot_date,
    MAX(ts.schema_name) AS schema_name,
    MAX(ts.table_name) AS table_name,
    MAX(ts.layer) AS layer,
    MAX(ts.table_criticality) AS table_criticality,
    MAX(ts.dag_criticality) AS dag_criticality,
    MAX(ts.sla_deadline_localtime) AS sla_deadline_localtime,
    BOOL_OR(ts.is_delivered) AS is_delivered,
    BOOL_OR(ts.is_inside_declared_sla) AS is_inside_declared_sla,
    MIN(ts.ts_first_delivery_brt) AS ts_first_delivery_brt,
    MIN(ts.minutes_after_deadline) AS minutes_after_deadline,
    MAX(ts.sla_type) AS sla_type,
    MAX(ts.freshness_max_staleness_minutes) AS freshness_max_staleness_minutes,
    MAX(ts.freshness_active_window_localtime) AS freshness_active_window_localtime,
    MAX(ts.deliveries_count) AS deliveries_count,
    MAX(ts.freshness_observed_max_staleness_minutes) AS freshness_observed_max_staleness_minutes,
    ts.dt_snapshot,
    NOW() AS ts_load,
    YEAR(ts.dt_snapshot) AS year,
    MONTH(ts.dt_snapshot) AS month,
    DAY(ts.dt_snapshot) AS day
FROM
    datalake_pipeline.table_sla_information AS ts
WHERE
    ts.dt_snapshot BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY
    ts.id_table,
    ts.id_dag,
    ts.dt_snapshot
