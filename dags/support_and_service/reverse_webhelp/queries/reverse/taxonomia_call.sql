WITH ticket_calls AS (
    SELECT DISTINCT
        dc.sk_call,
        dc.sk_ticket
    FROM
        dw_teravoz.fact_calls AS dc
    WHERE
        dc.sk_ticket IS NOT NULL
),
last_queue AS (
    SELECT
        fc.sk_call,
        MAX(fc.ts_queue_joined_local) AS last_queue
    FROM
        dw_teravoz.fact_call_queues AS fc
    GROUP BY 1
),
calls_tickets AS (
    SELECT DISTINCT
        tc.sk_ticket,
        CAST(fc.queue_number AS VARCHAR(10)) AS dept
    FROM
        dw_teravoz.fact_call_queues AS fc
    INNER JOIN
        last_queue AS lq
            ON lq.sk_call = fc.sk_call
            AND lq.last_queue = fc.ts_queue_joined_local
    INNER JOIN
        ticket_calls AS tc
            ON tc.sk_call = fc.sk_call
    UNION
    SELECT
        ft.sk_ticket,
        fc.last_queue_name AS dept
    FROM
        dw_call.dim_call AS dc
    INNER JOIN
        dw_call.fact_calls AS fc
            ON fc.sk_call = dc.sk_call
    INNER JOIN (
        SELECT
            ft.sk_call,
            MAX(ft.sk_ticket) AS sk_ticket
        FROM
            dw_tickets.fact_tickets AS ft
        GROUP BY 1
    ) AS ft
        ON ft.sk_call = dc.sk_call
    WHERE
        has_ended_in_ura = FALSE
        AND is_answered = TRUE
),
tickets_areas AS (
    SELECT DISTINCT
        dt.sk_ticket,
        gdc.team AS ticket_area,
        dt.dept
    FROM
        calls_tickets AS dt
    INNER JOIN
        datalake_gsheets_clean.department_control AS gdc
            ON dt.dept = gdc.department
    WHERE
        team <> '-'
)
SELECT DISTINCT
    dt.ts_created_local AS `Data - Hora Local`,
    ft.sk_ticket AS `Ticket Id`,
    dt.channel AS Canal,
    gdc.dept AS Fila,
    step_tag AS Step,
    customer_type_tag AS Client,
    contact_motivation_tag AS Motivation,
    contact_theme_tag AS Theme,
    contact_theme_detail_tag AS ThemeDetail,
    gdc.ticket_area AS Area,
    'new' AS taxonomy_version,
    YEAR(CURRENT_DATE - 1) AS year,
    MONTH(CURRENT_DATE - 1) AS month,
    DAY(CURRENT_DATE - 1) AS day,
    NOW() AS ts_load
FROM
    dw_tickets.fact_tickets AS ft
INNER JOIN
    dw_public.dim_date AS dd
        ON ft.sk_created_date_local = dd.sk_date
INNER JOIN
    dw_tickets.dim_ticket AS dt
        ON dt.sk_ticket = ft.sk_ticket
INNER JOIN
    tickets_areas AS gdc
        ON dt.sk_ticket = gdc.sk_ticket
WHERE
    DATE(dd.date) = CURRENT_DATE() - 1
    AND customer_type_tag IS NOT NULL
    AND contact_motivation_tag IS NOT NULL
    AND contact_theme_tag IS NOT NULL
    AND dt.agent_organization IN ('webhelp', 'webhelpbr')
    AND dt.channel = 'call'