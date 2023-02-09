WITH agents_info AS (
    SELECT
        ac.id_assignee AS assignee_id,
        ac.email,
        ac.agent_name AS nome,
        ac.department AS departamento,
        CASE
            WHEN ac.agent_company ILIKE '%concentrix%' THEN 'concentrix'
            WHEN ac.agent_company ILIKE '%atento%' THEN 'atento'
            ELSE 'quintoandar'
        END AS centro_de_custo
    FROM
        datalake_gsheets_clean.agents_control AS ac
    GROUP BY 1, 2, 3, 4, 5
),
automatically_closed_emails AS (
    SELECT DISTINCT
        tt.sk_ticket
    FROM
        dw_tickets.fact_ticket_tags AS tt
    INNER JOIN
        dw_tickets.dim_ticket AS dt
        ON dt.sk_ticket = tt.sk_ticket
    WHERE
        dt.channel IN ('email', 'form_faq', 'web', 'other')
        AND tt.ticket_tag IN (
            'resolve_ticket_acompanhamento','fechado_automaticamente_noreply', 'redirecionado_atendimento_2',
            'closed_by_merge', 'zapdesk', 'ticket_via_call', 'call_contato_receptivo', 'call_contato_ativo',
            'resolve_ticket_acompanhamento', 'redirecionado_adm_v1', 'robotserviceaccount02'
        )
),
ticket_calls AS (
    SELECT
        dc.sk_call,
        dc.sk_ticket
    FROM
        dw_teravoz.fact_calls AS  dc
    WHERE
        dc.sk_ticket IS NOT NULL
    GROUP BY 1, 2
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
    SELECT
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
    GROUP BY 1, 2
),
last_task AS (
    SELECT
        t.id_channel,
        MAX(t.ts_created) AS last_timestamp
    FROM
        datalake_quinto_messenger.task AS t
    GROUP BY 1
),
chat_tickets AS (
    SELECT
        fc.sk_ticket,
        fc.last_chat_department AS dept
    FROM
        historical_dw_zendesk.fact_chats AS fc
    INNER JOIN
        historical_dw_zendesk.dim_chat AS dc
            ON dc.sk_chat = fc.sk_chat
    WHERE
        DATE(dc.ts_started_local) <= '2020-08-20'
    GROUP BY 1, 2
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
email_tickets AS (
    SELECT
        dt.sk_ticket,
        dt.group_name AS dept
    FROM
        dw_tickets.dim_ticket AS dt
    WHERE
        dt.channel NOT IN ('call', 'chat')
    GROUP BY 1, 2
),
dept_tickets AS (
    SELECT
        *
    FROM
        email_tickets
    UNION
    SELECT
        *
    FROM
        chat_tickets
    UNION
    SELECT
        *
    FROM
        calls_tickets
),
tickets_areas AS (
    SELECT
        dt.sk_ticket,
        gdc.team AS ticket_area,
        dt.dept
    FROM
        dept_tickets AS dt
    INNER JOIN
        datalake_gsheets_clean.department_control AS gdc
            ON dt.dept = gdc.department
    WHERE
        team <> '-'
    GROUP BY 1,2,3
)
SELECT
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
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
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
INNER JOIN
    agents_info AS ai
        ON ai.assignee_id = ft.sk_zendesk_assignee_user
WHERE
    DATE(dd.date) = CURRENT_DATE() - 1
    AND dt.sk_ticket NOT IN (SELECT * FROM automatically_closed_emails)
    AND customer_type_tag IS NOT NULL
    AND contact_motivation_tag IS NOT NULL
    AND contact_theme_tag IS NOT NULL
    AND ai.centro_de_custo = 'atento'
    AND dt.channel = 'chat'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
