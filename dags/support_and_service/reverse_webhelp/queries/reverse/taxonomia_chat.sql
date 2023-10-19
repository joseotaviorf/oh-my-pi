WITH last_task AS (
    SELECT
        t.id_channel,
        MAX(t.ts_created) AS last_timestamp
    FROM
        datalake_quinto_messenger.task AS t
    GROUP BY 1
),
chat_tickets AS (
    SELECT DISTINCT
        fc.sk_ticket,
        fc.last_chat_department AS dept
    FROM
        historical_dw_zendesk.fact_chats AS fc
    INNER JOIN
        historical_dw_zendesk.dim_chat AS dc
            ON dc.sk_chat = fc.sk_chat
    WHERE
        DATE(dc.ts_started_local) <= '2020-08-20'
    UNION
    SELECT
        ft.sk_ticket,
        task_queue_name AS dept
    FROM
        datalake_quinto_messenger.task AS t
    INNER JOIN
        last_task AS lt
            ON lt.id_channel = t.id_channel
            AND t.ts_created = lt.last_timestamp
    INNER JOIN (
        SELECT
            task_queue_name,
            id_task
        FROM
            datalake_quinto_messenger.task_event
        GROUP BY 1, 2
    ) AS te
        ON te.id_task = t.id_task
    INNER JOIN
        dw_tickets.fact_tickets AS ft
            ON ft.sk_session = t.id_conversation
            AND ft.sk_session > 0
    INNER JOIN
        dw_tickets.dim_ticket AS dt
            ON dt.sk_ticket = ft.sk_ticket
    WHERE
        dt.channel IN ('chat')
        AND DATE(dt.ts_created_local) >= '2020-08-21'
    GROUP BY 1,2
),
tickets_areas AS (
    SELECT DISTINCT
        dt.sk_ticket,
        gdc.team AS ticket_area,
        dt.dept
    FROM
        chat_tickets AS dt
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
    dt.customer_type_tag AS Client,
    dt.contact_motivation_tag AS Motivation,
    dt.contact_theme_tag AS Theme,
    dt.contact_theme_detail_tag AS ThemeDetail,
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