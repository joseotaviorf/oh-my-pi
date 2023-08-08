WITH zendesk_tickets AS (
    SELECT
        t.id_ticket,
        t.id_assignee,
        t.subject,
        t.description,
        t.ticket_via,
        CASE
            WHEN t.ticket_via IN ('api', 'web')
                AND (tags LIKE '%call_contato_ativo%'
                    OR tags LIKE '%call_contato_receptivo%'
                ) THEN 'call'
            WHEN t.ticket_via IN ('api')
                AND tags LIKE '%form%' THEN 'form_faq'
            WHEN t.ticket_via IN ('web', 'email', 'chat', 'whatsapp') THEN t.ticket_via
            ELSE 'other'
        END AS channel,
        t.priority,
        t.recipient,
        t.tags,
        t.status,
        t.type AS ticket_type,
        t.id_group,
        COALESCE(CAST(t.is_public AS BOOLEAN), FALSE) AS has_public_comments,
        CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.score') AS STRING) AS score,
        CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.reason') AS STRING) AS reason,
        CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.comment') AS STRING) AS comment,
        t.ts_created,
        t.ts_created_local,
        t.ts_updated,
        FROM_UTC_TIMESTAMP(t.ts_updated, 'Brazil/East') AS ts_updated_local,
        YEAR(t.ts_updated) AS year,
        MONTH(t.ts_updated) AS month,
        DAY(t.ts_updated) AS day
    FROM
        datalake_zendesk_tickets_clean.tickets AS t
    WHERE
        t.ticket_via != 'api'
        OR (
            t.ticket_via = 'api'
            AND t.tags NOT LIKE '%hsm%'
        )
        AND DATE(t.ts_created) >= "2020-01-01"
),
agents_control AS (
    SELECT
        t.id_ticket,
        -- 5124274148 is bot id
        CASE
            WHEN t.id_assignee = "5124274148" THEN COALESCE(a.id_agent, 5124274148)
            ELSE t.id_assignee
        END AS id_agent,
        a.email,
        a.name,
        a.phone,
        a.organization,
        a.ts_created,
        a.ts_updated
    FROM
        datalake_zendesk_tickets_clean.tickets AS t
    LEFT JOIN
        datalake_zendesk_custom_fields.custom_fields AS cf
            ON t.id_ticket = cf.id_ticket
    LEFT JOIN
        datalake_zendesk_users.agents AS a
            ON cf.custom_fields['[AUTO] Email do Agente'] = a.email
),
custom_fields_exploded AS (
    SELECT
        id_ticket,
        EXPLODE(custom_fields)
    FROM
        datalake_zendesk_custom_fields.custom_fields
),
sale_offers_keys AS (
    SELECT
        cfe.id_ticket,
        so.id_offer
    FROM
        custom_fields_exploded AS cfe
    JOIN
        datalake_sale_offer_flows.sale_offer_flows AS so
            ON cfe.value = so.id_offer
)
SELECT
    t.id_ticket,
    sok.id_offer AS id_sale_offer,
    cf.custom_fields['[AQ] ID do Job '] AS id_job,
    cf.custom_fields['Ticket Problema ID'] AS id_problem_ticket,
    ac.id_agent,
    t.subject,
    t.description,
    t.ticket_via,
    t.channel,
    g.name AS group_name,
    t.priority,
    t.recipient,
    t.tags,
    t.status,
    t.ticket_type,
    t.has_public_comments,
    t.score,
    t.reason,
    t.comment,
    TO_JSON(cf.custom_fields) AS custom_fields,
    cf.custom_fields['Tipo de Solicitação'] AS request_type,
    ac.name AS agent_name,
    ac.email AS agent_email,
    ac.phone AS agent_phone,
    ac.organization AS agent_organization,
    COALESCE(
        cf.custom_fields['Tipo de Cliente'],
        REPLACE(REPLACE(REPLACE(cf.custom_fields['[CC] - Tipo de Cliente'], 'cc_',''), 'er_', 'er'), 'serviços', 'serviço'),
        cf.custom_fields['Tipo de Cliente [PRE-SAIDA]']
    ) AS client_type,
    SPLIT(cf.custom_fields['Classificação do atendimento (Tags)'], '__')[0] AS step_tag,
    COALESCE(
        SPLIT(cf.custom_fields['Classificação do atendimento (Tags)'], '__')[1],
        cf.custom_fields['Cliente Tag']
    ) AS customer_type_tag,
    COALESCE(
        SPLIT(cf.custom_fields['Classificação do atendimento (Tags)'], '__')[3],
        cf.custom_fields['Motivo Tag'],
        cf.custom_fields['[CC] - Motivo do contato']
    ) AS contact_motivation_tag,
    SPLIT(cf.custom_fields['Classificação do atendimento (Tags)'], '__')[4] AS contact_theme_detail_tag,
    COALESCE(
        SPLIT(cf.custom_fields['Classificação do atendimento (Tags)'], '__')[2],
        cf.custom_fields['Assunto Tag'],
        cf.custom_fields['Tipo de Solicitação'],
        cf.custom_fields['[CC] - Assunto do Contato'],
        cf.custom_fields['[NG] Tipo de solicitação (IGPM/IPCA)'],
        cf.custom_fields['[PAY] Tipo de Solicitação'],
        cf.custom_fields['Tema do DM']
    ) AS contact_theme_tag,
    ac.ts_created AS ts_agent_started,
    t.ts_created,
    t.ts_created_local,
    t.ts_updated,
    t.ts_updated_local,
    t.year,
    t.month,
    t.day
FROM
    zendesk_tickets AS t
LEFT JOIN
    datalake_zendesk_tickets_clean.groups AS g
        ON t.id_group = g.id_group
LEFT JOIN
    datalake_zendesk_custom_fields.custom_fields AS cf
        ON t.id_ticket = cf.id_ticket
LEFT JOIN
    sale_offers_keys AS sok
        ON t.id_ticket = sok.id_ticket
LEFT JOIN
    agents_control AS ac
        ON t.id_ticket = ac.id_ticket
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY t.id_ticket ORDER BY t.ts_updated DESC) = 1
