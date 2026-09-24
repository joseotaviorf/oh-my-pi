WITH first_declared AS (
    SELECT
        t.id_table,
        t.id_dag,
        t.id_task,
        MIN(t.dt_last_updated) AS dt_first_declared
    FROM
        datalake_pipeline.table AS t
    GROUP BY
        t.id_table,
        t.id_dag,
        t.id_task
),
scoped AS (
    SELECT DISTINCT
        t.id_table,
        t.id_dag,
        t.id_task,
        t.schema AS schema_name,
        t.table_name,
        t.layer,
        t.sla_deadline_localtime AS table_sla_deadline_localtime,
        ds.id_line,
        ds.dt_snapshot,
        ds.is_intraday_dag,
        COALESCE(t.criticality, ds.criticality, 'Medium') AS table_criticality,
        COALESCE(ds.criticality, 'Medium') AS dag_criticality,
        ds.sla_deadline_localtime AS dag_sla_deadline_localtime,
        pd.freshness_max_staleness_minutes,
        pd.freshness_active_window_localtime,
        IF(pd.freshness_max_staleness_minutes IS NOT NULL, 'freshness', 'deadline') AS sla_type
    FROM
        datalake_pipeline.table AS t
    JOIN
        datalake_pipeline.dag_sla_information AS ds
            ON ds.id_dag = t.id_dag
            AND ds.is_active_and_unpaused = TRUE
    LEFT JOIN
        datalake_pipeline.dag AS pd
            ON pd.id_dag = t.id_dag
    -- A table counts from the day after it first appears in the DAG inventory, so a
    -- backfill never scores today's tables on days before they existed.
    JOIN
        first_declared AS fd
            ON fd.id_table = t.id_table
            AND fd.id_dag = t.id_dag
            AND fd.id_task = t.id_task
            AND ds.dt_snapshot > fd.dt_first_declared
    WHERE
        t.is_active = TRUE
        AND MAKE_DATE(ds.year, ds.month, ds.day)
            BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
resolved AS (
    SELECT
        sc.*,
        -- Freshness tables have no deadline. Otherwise a table-specific deadline wins,
        -- then the DAG deadline when the table keeps the DAG tier, then the tier
        -- default: 08:00 for Critical and High, 11:00 for Medium and Low.
        CASE
            WHEN sc.sla_type = 'freshness' THEN NULL
            WHEN sc.table_sla_deadline_localtime IS NOT NULL
                THEN sc.table_sla_deadline_localtime
            WHEN sc.table_criticality = sc.dag_criticality
                AND sc.dag_sla_deadline_localtime IS NOT NULL
                THEN sc.dag_sla_deadline_localtime
            WHEN sc.table_criticality IN ('Critical', 'High') THEN '08:00'
            ELSE '11:00'
        END AS sla_deadline_localtime,
        SPLIT(sc.freshness_active_window_localtime, '-')[0] AS freshness_window_start_localtime,
        SPLIT(sc.freshness_active_window_localtime, '-')[1] AS freshness_window_end_localtime
    FROM
        scoped AS sc
),
expected AS (
    SELECT
        r.*,
        CAST(
            CONCAT(CAST(r.dt_snapshot AS STRING), ' ', r.sla_deadline_localtime, ':00')
            AS TIMESTAMP
        ) AS ts_deadline_brt,
        -- Deliveries count toward dt_snapshot only inside this window: the freshness
        -- active window, or the 20:55-to-20:55 nightly cycle for deadline tables.
        CASE
            WHEN r.sla_type = 'freshness' THEN CAST(
                CONCAT(CAST(r.dt_snapshot AS STRING), ' ', r.freshness_window_start_localtime, ':00')
                AS TIMESTAMP
            )
            ELSE CAST(
                CONCAT(CAST(DATE_SUB(r.dt_snapshot, 1) AS STRING), ' 20:55:00') AS TIMESTAMP
            )
        END AS ts_window_start_brt,
        CASE
            WHEN r.sla_type = 'freshness' AND r.freshness_window_end_localtime = '24:00'
                THEN CAST(DATE_ADD(r.dt_snapshot, 1) AS TIMESTAMP)
            WHEN r.sla_type = 'freshness' THEN CAST(
                CONCAT(CAST(r.dt_snapshot AS STRING), ' ', r.freshness_window_end_localtime, ':00')
                AS TIMESTAMP
            )
            ELSE CAST(
                CONCAT(CAST(r.dt_snapshot AS STRING), ' 20:55:00') AS TIMESTAMP
            )
        END AS ts_window_end_brt
    FROM
        resolved AS r
),
task_successes AS (
    SELECT DISTINCT
        ti.id_dag,
        ti.id_task,
        FROM_UTC_TIMESTAMP(ti.ts_ended, 'America/Sao_Paulo') AS ts_delivery_brt
    FROM
        datalake_airflow.task_instance AS ti
    WHERE
        ti.task_state = 'success'
        AND ti.ts_ended IS NOT NULL
        AND MAKE_DATE(ti.year, ti.month, ti.day)
            BETWEEN DATE_SUB(DATE('{load_start_date}'), 1)
            AND DATE_ADD(DATE('{load_end_date}'), 1)
),
log_successes AS (
    SELECT DISTINCT
        l.id_dag,
        l.id_task,
        FROM_UTC_TIMESTAMP(TIMESTAMP(l.ts_event), 'America/Sao_Paulo') AS ts_delivery_brt
    FROM
        datalake_airflow.log AS l
    WHERE
        l.event = 'success'
        AND MAKE_DATE(l.year, l.month, l.day)
            BETWEEN DATE_SUB(DATE('{load_start_date}'), 1)
            AND DATE_ADD(DATE('{load_end_date}'), 1)
),
task_deliveries AS (
    SELECT id_dag, id_task, ts_delivery_brt FROM task_successes
    UNION
    SELECT id_dag, id_task, ts_delivery_brt FROM log_successes
),
delivery_events AS (
    SELECT
        e.id_table,
        e.id_dag,
        e.dt_snapshot,
        e.ts_window_start_brt,
        td.ts_delivery_brt
    FROM
        expected AS e
    JOIN
        task_deliveries AS td
            ON td.id_dag = e.id_dag
            AND td.id_task = e.id_task
    WHERE
        td.ts_delivery_brt >= e.ts_window_start_brt
        AND td.ts_delivery_brt < e.ts_window_end_brt
),
delivery_gaps AS (
    SELECT
        de.id_table,
        de.id_dag,
        de.dt_snapshot,
        de.ts_delivery_brt,
        (
            UNIX_TIMESTAMP(de.ts_delivery_brt)
            - UNIX_TIMESTAMP(
                COALESCE(
                    LAG(de.ts_delivery_brt) OVER (
                        PARTITION BY de.id_table, de.id_dag, de.dt_snapshot
                        ORDER BY de.ts_delivery_brt
                    ),
                    de.ts_window_start_brt
                )
            )
        ) / 60 AS minutes_since_previous_delivery
    FROM
        delivery_events AS de
),
deliveries AS (
    SELECT
        id_table,
        id_dag,
        dt_snapshot,
        MIN(ts_delivery_brt) AS ts_first_delivery_brt,
        MAX(ts_delivery_brt) AS ts_last_delivery_brt,
        COUNT(DISTINCT DATE_TRUNC('MINUTE', ts_delivery_brt)) AS deliveries_count,
        MAX(minutes_since_previous_delivery) AS max_minutes_between_deliveries
    FROM
        delivery_gaps
    GROUP BY
        id_table,
        id_dag,
        dt_snapshot
),
scored AS (
    SELECT
        e.*,
        dv.ts_first_delivery_brt,
        COALESCE(dv.deliveries_count, 0) AS deliveries_count,
        -- Longest stretch without a delivery in the elapsed part of the active window,
        -- including the open stretch from the last delivery to the window end or now.
        CASE
            WHEN e.sla_type <> 'freshness' THEN NULL
            WHEN FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo') <= e.ts_window_start_brt
                THEN NULL
            ELSE ROUND(
                GREATEST(
                    COALESCE(dv.max_minutes_between_deliveries, 0),
                    (
                        UNIX_TIMESTAMP(
                            LEAST(e.ts_window_end_brt, FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo'))
                        )
                        - UNIX_TIMESTAMP(COALESCE(dv.ts_last_delivery_brt, e.ts_window_start_brt))
                    ) / 60
                ),
                0
            )
        END AS freshness_observed_max_staleness_minutes
    FROM
        expected AS e
    LEFT JOIN
        deliveries AS dv
            ON dv.id_table = e.id_table
            AND dv.id_dag = e.id_dag
            AND dv.dt_snapshot = e.dt_snapshot
)
SELECT
    s.id_table,
    s.id_dag,
    s.id_task,
    s.id_line,
    s.schema_name,
    s.table_name,
    s.layer,
    s.table_criticality,
    s.dag_criticality,
    s.sla_deadline_localtime,
    s.is_intraday_dag,
    s.ts_first_delivery_brt IS NOT NULL AS is_delivered,
    CASE
        WHEN s.sla_type = 'freshness' THEN
            CASE
                WHEN s.freshness_observed_max_staleness_minutes IS NULL THEN NULL
                WHEN s.freshness_observed_max_staleness_minutes > s.freshness_max_staleness_minutes THEN FALSE
                WHEN FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo') < s.ts_window_end_brt
                    THEN NULL
                ELSE TRUE
            END
        WHEN s.ts_first_delivery_brt IS NOT NULL
            AND s.ts_first_delivery_brt <= s.ts_deadline_brt THEN TRUE
        WHEN s.ts_first_delivery_brt IS NOT NULL THEN FALSE
        WHEN FROM_UTC_TIMESTAMP(NOW(), 'America/Sao_Paulo')
            <= s.ts_deadline_brt THEN NULL
        ELSE FALSE
    END AS is_inside_declared_sla,
    ROUND(
        (
            UNIX_TIMESTAMP(s.ts_first_delivery_brt)
            - UNIX_TIMESTAMP(s.ts_deadline_brt)
        ) / 60,
        0
    ) AS minutes_after_deadline,
    s.ts_deadline_brt,
    s.ts_first_delivery_brt,
    s.sla_type,
    s.freshness_max_staleness_minutes,
    s.freshness_active_window_localtime,
    s.deliveries_count,
    s.freshness_observed_max_staleness_minutes,
    s.dt_snapshot,
    NOW() AS ts_load,
    YEAR(s.dt_snapshot) AS year,
    MONTH(s.dt_snapshot) AS month,
    DAY(s.dt_snapshot) AS day
FROM
    scored AS s
