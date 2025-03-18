WITH weekends_and_holidays AS (
    SELECT
        ad.date AS dt_non_working
    FROM
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.weekend = 'Weekend'
    UNION
    SELECT
        sch.dt_holiday AS dt_non_working
    FROM
        datalake_gsheets_clean.service_city_holidays AS sch
    WHERE
        sch.category = 'Nacional'
),
ticket_sla_target AS (
    SELECT
    t.id_ticket,
    MAX(
        CASE
            WHEN t.group_name IN ('Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]') THEN 21
            ELSE COALESCE(tgs.sla, tds.sla, ths.sla, jrs.sla)
        END
    ) AS sla_target,
    MAX(
        CASE
            WHEN CAST(t.dt_budgeted AS TIMESTAMP) IS NOT NULL
                AND CAST(t.dt_budgeted AS TIMESTAMP) >= t.ts_created - INTERVAL 3 HOUR
                AND CAST(t.dt_budgeted AS TIMESTAMP) < COALESCE(t.ts_solved, TIMESTAMP('{load_end_date}')) THEN CAST(t.dt_budgeted AS TIMESTAMP)
            ELSE t.ts_created - INTERVAL 3 HOUR
        END
    ) AS ts_sla_started,
    t.ts_solved
    FROM
        datalake_zendesk.tickets_current AS t
    LEFT JOIN
        datalake_gsheets_clean.department_control AS dc
            ON dc.department = t.group_name
    LEFT JOIN
        datalake_gsheets_clean.tag_sla_target AS tgs
            ON dc.journey_step = tgs.journey
            AND t.tags LIKE CONCAT('%', tgs.tag, '%')
            AND t.ts_created BETWEEN tgs.dt_start AND COALESCE(tgs.dt_end, TIMESTAMP('{load_end_date}'))
    LEFT JOIN
        datalake_customer_support.sla_theme_detail AS tds
            ON dc.journey_step = tds.journey_step
            AND t.contact_theme_detail_tag = tds.theme_detail
            AND DATE(t.ts_created) BETWEEN tds.dt_start AND COALESCE(tds.dt_end, TIMESTAMP('{load_end_date}'))
    LEFT JOIN
        datalake_customer_support.sla_theme AS ths
            ON dc.journey_step = ths.journey_step
            AND t.contact_theme_tag = ths.theme
            AND DATE(t.ts_created) BETWEEN ths.dt_start AND COALESCE(ths.dt_end, TIMESTAMP('{load_end_date}'))
    LEFT JOIN
        datalake_customer_support.sla_journey AS jrs
            ON dc.journey_step = jrs.journey_step
            AND DATE(t.ts_created) BETWEEN jrs.dt_start AND COALESCE(jrs.dt_end, TIMESTAMP('{load_end_date}'))
    WHERE
        t.tags NOT LIKE '%robotserviceaccount02%'
        AND (
            (
                t.group_name = 'Offboarding Reparos [OFF] [POS] [BACK]'
                AND t.tags LIKE '%orçamentação_realizada%'
            )
            OR t.group_name != 'Offboarding Reparos [OFF] [POS] [BACK]'
        )
        AND ts_created >= DATE('{load_start_date}') - INTERVAL 3 MONTH
    GROUP BY ALL
),
ticket_date_intervals AS (
    SELECT
        id_ticket,
        MAX(sla_target) OVER(PARTITION BY id_ticket) AS sla_target,
        SEQUENCE(
            IF(DATE(ts_sla_started) < DATE('{load_start_date}'), DATE('{load_start_date}'), DATE(ts_sla_started)),
            COALESCE(DATE(ts_solved), DATE('{load_end_date}'))
        ) AS dt_interval,
        ARRAY_INTERSECT(
            dt_interval,
            (SELECT ARRAY_AGG(dt_non_working) FROM weekends_and_holidays)
        ) AS days_off_arr,
        ts_sla_started,
        ts_solved
    FROM
        ticket_sla_target
    WHERE
        sla_target IS NOT NULL
),
ticket_daily_snapshot AS (
    SELECT
        id_ticket,
        EXPLODE(dt_interval) AS dt_snapshot,
        sla_target,
        ts_sla_started,
        ts_solved
    FROM
        ticket_date_intervals
),
ticket_days_off AS (
    SELECT
        id_ticket,
        EXPLODE(days_off_arr) AS dt_off
    FROM
        ticket_date_intervals
),
elapsed_days AS (
    SELECT
        tds.id_ticket,
        tds.dt_snapshot,
        tdo.dt_off,
        COUNT(dt_snapshot) OVER(
        PARTITION BY tds.id_ticket ORDER BY tds.dt_snapshot ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) - 1 AS days_elapsed_calendar,
        COUNT(dt_off) OVER(
        PARTITION BY tds.id_ticket ORDER BY tds.dt_snapshot ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )AS days_elapsed_off,
        COALESCE(DATE(tds.ts_solved), DATE("1999-01-01")) = tds.dt_snapshot AS is_solved,
        tds.sla_target,
        tds.ts_sla_started,
        tds.ts_solved
    FROM
        ticket_daily_snapshot AS tds
    LEFT JOIN
        ticket_days_off AS tdo
        ON tds.id_ticket = tdo.id_ticket
        AND tds.dt_snapshot = tdo.dt_off
)
SELECT
    id_ticket,
    dt_snapshot,
    dt_off,
    days_elapsed_calendar,
    days_elapsed_off,
    CASE
        WHEN days_elapsed_calendar - days_elapsed_off >= 0 THEN days_elapsed_calendar - days_elapsed_off
        ELSE 0
    END AS days_elapsed_business,
    sla_target,
    is_solved,
    CASE
        WHEN (days_elapsed_calendar - days_elapsed_off) <= sla_target THEN TRUE
        ELSE FALSE
    END AS is_backlog_in_time,
    ts_sla_started,
    ts_solved
FROM
    elapsed_days