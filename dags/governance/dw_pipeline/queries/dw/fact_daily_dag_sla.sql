WITH dag_rollup AS (
    SELECT
        ds.id_dag,
        ds.dt_snapshot,
        MAX(ds.id_line) AS id_line,
        MAX(ds.criticality) AS criticality,
        MAX(ds.sla_deadline_localtime) AS sla_deadline_localtime,
        BOOL_OR(ds.is_active_and_unpaused) AS is_active_and_unpaused,
        BOOL_OR(ds.is_in_ignoring_list) AS is_in_ignoring_list,
        BOOL_OR(ds.is_executed) AS is_executed,
        BOOL_OR(ds.is_run_successful) AS is_run_successful,
        BOOL_OR(ds.is_inside_sla) AS is_inside_sla
    FROM
        datalake_pipeline.dag_sla_information AS ds
    WHERE
        ds.dt_snapshot BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        ds.id_dag,
        ds.dt_snapshot
),
table_rollup AS (
    -- A DAG is inside its declared SLA when every measured table of that DAG is.
    -- A miss outranks an undecided table; no measured tables means no verdict.
    SELECT
        ts.id_dag,
        ts.dt_snapshot,
        CASE
            WHEN BOOL_OR(ts.is_inside_declared_sla = FALSE) THEN FALSE
            WHEN BOOL_OR(ts.is_inside_declared_sla IS NULL) THEN NULL
            ELSE TRUE
        END AS is_inside_declared_sla,
        MAX(ts.ts_first_delivery_brt) AS ts_first_successful_delivery_brt
    FROM
        datalake_pipeline.table_sla_information AS ts
    WHERE
        ts.dt_snapshot BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        ts.id_dag,
        ts.dt_snapshot
)
SELECT
    dr.id_dag AS sk_dag,
    dr.id_line AS sk_line,
    BIGINT(DATE_FORMAT(dr.dt_snapshot, 'yyyyMMdd')) AS sk_snapshot_date,
    dr.criticality,
    dr.sla_deadline_localtime,
    dr.is_active_and_unpaused,
    dr.is_in_ignoring_list,
    dr.is_executed,
    dr.is_run_successful,
    dr.is_inside_sla,
    tr.is_inside_declared_sla,
    tr.ts_first_successful_delivery_brt,
    dr.dt_snapshot,
    NOW() AS ts_load,
    YEAR(dr.dt_snapshot) AS year,
    MONTH(dr.dt_snapshot) AS month,
    DAY(dr.dt_snapshot) AS day
FROM
    dag_rollup AS dr
LEFT JOIN
    table_rollup AS tr
        ON tr.id_dag = dr.id_dag
        AND tr.dt_snapshot = dr.dt_snapshot
