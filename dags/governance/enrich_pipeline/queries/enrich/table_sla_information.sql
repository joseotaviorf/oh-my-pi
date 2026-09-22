WITH expected AS (
    SELECT DISTINCT
        t.id_table,
        t.id_dag,
        t.id_task,
        t.schema AS schema_name,
        t.table_name,
        t.layer,
        t.criticality AS table_criticality,
        ds.id_line,
        ds.dt_snapshot,
        ds.criticality AS dag_criticality,
        ds.sla_deadline_localtime,
        ds.is_intraday_dag,
        CAST(
            CONCAT(
                CAST(ds.dt_snapshot AS STRING),
                ' ',
                ds.sla_deadline_localtime,
                ':00'
            ) AS TIMESTAMP
        ) AS ts_deadline_brt
    FROM
        datalake_pipeline.table AS t
    JOIN
        datalake_pipeline.dag_sla_information AS ds
            ON ds.id_dag = t.id_dag
            AND ds.is_active_and_unpaused = TRUE
            AND ds.is_in_ignoring_list = FALSE
    WHERE
        t.is_active = TRUE
        AND ds.sla_deadline_localtime IS NOT NULL
        AND MAKE_DATE(ds.year, ds.month, ds.day)
            BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
deliveries AS (
    SELECT
        e.id_table,
        e.id_dag,
        e.dt_snapshot,
        MIN(
            FROM_UTC_TIMESTAMP(
                ev.ts_event_created,
                'America/Sao_Paulo'
            )
        ) AS ts_first_delivery_brt
    FROM
        expected AS e
    JOIN
        datalake_astro_clean.dataset AS d
            ON d.uri = e.id_table
    JOIN
        datalake_astro_clean.dataset_event AS ev
            ON ev.id_dataset = d.id
            AND ev.id_source_dag = e.id_dag
            AND ev.id_source_task = e.id_task
            AND FROM_UTC_TIMESTAMP(
                ev.ts_event_created,
                'America/Sao_Paulo'
            ) >= CAST(
                CONCAT(
                    CAST(DATE_SUB(e.dt_snapshot, 1) AS STRING),
                    ' 20:55:00'
                ) AS TIMESTAMP
            )
            AND FROM_UTC_TIMESTAMP(
                ev.ts_event_created,
                'America/Sao_Paulo'
            ) < CAST(
                CONCAT(
                    CAST(e.dt_snapshot AS STRING),
                    ' 20:55:00'
                ) AS TIMESTAMP
            )
    WHERE
        MAKE_DATE(ev.year, ev.month, ev.day)
            BETWEEN DATE_SUB(DATE('{load_start_date}'), 1)
            AND DATE('{load_end_date}')
    GROUP BY
        e.id_table,
        e.id_dag,
        e.dt_snapshot
)
SELECT
    e.id_table,
    e.id_dag,
    e.id_task,
    e.id_line,
    e.schema_name,
    e.table_name,
    e.layer,
    e.table_criticality,
    e.dag_criticality,
    e.sla_deadline_localtime,
    e.is_intraday_dag,
    dv.ts_first_delivery_brt IS NOT NULL AS is_delivered,
    CASE
        WHEN dv.ts_first_delivery_brt IS NOT NULL
            AND dv.ts_first_delivery_brt <= e.ts_deadline_brt THEN TRUE
        WHEN dv.ts_first_delivery_brt IS NOT NULL THEN FALSE
        WHEN FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo')
            <= e.ts_deadline_brt THEN NULL
        ELSE FALSE
    END AS is_inside_declared_sla,
    ROUND(
        (
            UNIX_TIMESTAMP(dv.ts_first_delivery_brt)
            - UNIX_TIMESTAMP(e.ts_deadline_brt)
        ) / 60,
        0
    ) AS minutes_after_deadline,
    e.ts_deadline_brt,
    dv.ts_first_delivery_brt,
    e.dt_snapshot,
    NOW() AS ts_load,
    YEAR(e.dt_snapshot) AS year,
    MONTH(e.dt_snapshot) AS month,
    DAY(e.dt_snapshot) AS day
FROM
    expected AS e
LEFT JOIN
    deliveries AS dv
        ON dv.id_table = e.id_table
        AND dv.id_dag = e.id_dag
        AND dv.dt_snapshot = e.dt_snapshot
