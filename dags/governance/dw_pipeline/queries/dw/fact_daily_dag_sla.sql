SELECT
    ds.id_dag AS sk_dag,
    MAX(ds.id_line) AS sk_line,
    BIGINT(DATE_FORMAT(ds.dt_snapshot, 'yyyyMMdd')) AS sk_snapshot_date,
    MAX(ds.criticality) AS criticality,
    MAX(ds.sla_deadline_localtime) AS sla_deadline_localtime,
    BOOL_OR(ds.is_active_and_unpaused) AS is_active_and_unpaused,
    BOOL_OR(ds.is_in_ignoring_list) AS is_in_ignoring_list,
    BOOL_OR(ds.is_executed) AS is_executed,
    BOOL_OR(ds.is_run_successful) AS is_run_successful,
    BOOL_OR(ds.is_inside_sla) AS is_inside_sla,
    BOOL_OR(ds.is_inside_declared_sla) AS is_inside_declared_sla,
    MIN(ds.ts_last_table_task_successful_brt) AS ts_first_successful_delivery_brt,
    ds.dt_snapshot,
    NOW() AS ts_load,
    YEAR(ds.dt_snapshot) AS year,
    MONTH(ds.dt_snapshot) AS month,
    DAY(ds.dt_snapshot) AS day
FROM
    datalake_pipeline.dag_sla_information AS ds
WHERE
    ds.dt_snapshot BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND ds.criticality IS NOT NULL
GROUP BY
    ds.id_dag,
    ds.dt_snapshot
