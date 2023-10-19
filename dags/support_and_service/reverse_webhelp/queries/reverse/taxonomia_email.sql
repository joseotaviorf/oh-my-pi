WITH automatically_closed_emails AS (
    SELECT DISTINCT
        tt.sk_ticket
    FROM
        dw_tickets.fact_ticket_tags AS tt
    JOIN
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
email_tickets AS (
    SELECT DISTINCT
        dt.sk_ticket,
        dt.group_name AS dept
    FROM
        dw_tickets.dim_ticket AS dt
    WHERE
        dt.channel NOT IN ('call', 'chat')
),
tickets_areas AS (
    SELECT DISTINCT
        dt.sk_ticket,
        gdc.team AS ticket_area,
        dt.dept
    FROM
        email_tickets AS dt
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
JOIN
    dw_public.dim_date AS dd
        on ft.sk_created_date_local = dd.sk_date
JOIN
    dw_tickets.dim_ticket AS dt
        on dt.sk_ticket = ft.sk_ticket
JOIN
    tickets_areas AS gdc
        ON dt.sk_ticket = gdc.sk_ticket
WHERE
    DATE(dd.date) = CURRENT_DATE() - 1
    AND dt.sk_ticket NOT IN (SELECT * FROM automatically_closed_emails)
    AND customer_type_tag IS NOT NULL
    AND contact_motivation_tag IS NOT NULL
    AND contact_theme_tag IS NOT NULL
    AND dt.agent_organization IN ('webhelp', 'webhelpbr')
    AND dt.channel IN ('web','other','email','form_faq')
