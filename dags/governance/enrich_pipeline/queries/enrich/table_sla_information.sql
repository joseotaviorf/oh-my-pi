WITH scoped AS (
    SELECT DISTINCT
        t.id_table,
        t.id_dag,
        t.id_task,
        t.schema AS schema_name,
        t.table_name,
        t.layer,
        ds.id_line,
        ds.dt_snapshot,
        ds.is_intraday_dag,
        COALESCE(t.criticality, ds.criticality, 'Medium') AS table_criticality,
        COALESCE(ds.criticality, 'Medium') AS dag_criticality,
        ds.sla_deadline_localtime AS dag_sla_deadline_localtime
    FROM
        datalake_pipeline.table AS t
    JOIN
        datalake_pipeline.dag_sla_information AS ds
            ON ds.id_dag = t.id_dag
            AND ds.is_active_and_unpaused = TRUE
    WHERE
        t.is_active = TRUE
        AND MAKE_DATE(ds.year, ds.month, ds.day)
            BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
expected AS (
    SELECT
        s.*,
        CAST(
            CONCAT(CAST(s.dt_snapshot AS STRING), ' ', s.sla_deadline_localtime, ':00')
            AS TIMESTAMP
        ) AS ts_deadline_brt
    FROM (
        SELECT
            sc.*,
            -- A table that inherits its DAG's tier honours the DAG's declared deadline.
            -- A table that overrides the tier is judged by its own tier's default, because
            -- the DAG's deadline belongs to the DAG's tier. Defaults mirror
            -- CriticalityEnum.DEFAULT_DEADLINE_BY_TIER: Critical 08:00, everything else 11:00.
            CASE
                WHEN sc.table_criticality = sc.dag_criticality
                    AND sc.dag_sla_deadline_localtime IS NOT NULL
                    THEN sc.dag_sla_deadline_localtime
                WHEN sc.table_criticality = 'Critical' THEN '08:00'
                ELSE '11:00'
            END AS sla_deadline_localtime
        FROM scoped AS sc
    ) AS s
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
