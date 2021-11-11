WITH tickets_filter AS (
    SELECT DISTINCT
        t.*
    FROM
        datalake_zendesk_tickets_clean.tickets t
    WHERE
        (
            t.ticket_via <> 'api'
            OR (
                t.ticket_via = 'api'
                AND t.tags NOT LIKE '%hsm%'
            )
        )
),
historical_zendesk_chat AS (
    SELECT DISTINCT
        c.*
    FROM
        historical_datalake_zendesk_clean.chats c
    LEFT JOIN
        tickets_filter t
            ON t.id_ticket = c.id_ticket
    WHERE
        t.id_ticket IS NULL
),
last_updated_ticket as (
    SELECT
        id_ticket,
        MAX(ts_updated) AS ts_last_updated
    FROM
        tickets_filter
    GROUP BY 1
    UNION ALL
    SELECT
        id_ticket,
        MAX(ts_updated) AS ts_last_updated
    FROM   
        historical_zendesk_chat
    GROUP BY 1
),
last_updated_group AS (
    SELECT
        id_group,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_zendesk_tickets_clean.groups
    GROUP BY 1
),
distinct_groups AS (
    SELECT
        g.id_group,
        g.name,
        g.url_group
    FROM
        datalake_zendesk_tickets_clean.groups g
    INNER JOIN
        last_updated_group ge
            ON ge.id_group = g.id_group
            AND ge.ts_last_updated = g.ts_updated
    GROUP BY 1, 2, 3
),
union_historical_chat_with_zendesk AS (
    SELECT DISTINCT
        c.id_ticket,
        CONCAT("Chat with ", GET_JSON_OBJECT(c.visitor, "$.name")) AS subject,
        c.session AS description,
        "zendesk_chat" AS ticket_via,
        "chat" AS channel,
        c.department_name,
        NULL AS priority,
        NULL AS recipient,
        c.tags,
        "closed" AS status,
        c.id_department AS id_group,
        NULL AS has_public_comments,
        c.rating AS score,
        NULL AS reason,
        c.comment,
        c.ts_created,
        FROM_UTC_TIMESTAMP(c.ts_created, 'Brazil/East') AS ts_created_local,
        c.ts_updated,
        FROM_UTC_TIMESTAMP(c.ts_updated, 'Brazil/East') AS ts_updated_local,
        YEAR(c.ts_updated) AS year,
        MONTH(c.ts_updated) AS month,
        DAY(c.ts_updated) AS day
    FROM 
        historical_zendesk_chat c
    UNION ALL
    SELECT DISTINCT
        t.id_ticket,
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
            WHEN t.ticket_via IN ('web', 'email', 'chat') THEN t.ticket_via
            ELSE 'other'
        END AS channel,
        NULL AS department_name,
        t.priority,
        t.recipient,
        t.tags,
        t.status,
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
        tickets_filter t
)
SELECT DISTINCT
    te.id_ticket,
    t.subject,
    t.description,
    t.ticket_via,
    t.channel,
    COALESCE(g.name, t.department_name) AS group_name,
    t.priority,
    t.recipient,
    t.tags,
    t.status,
    t.has_public_comments,
    t.score,
    t.reason,
    t.comment,
    TO_JSON(cf.custom_fields) AS custom_fields,
    cf.custom_fields['Tipo de Solicitação'] AS request_type,
    COALESCE(
        cf.custom_fields['Tipo de Cliente'], 
        REPLACE(REPLACE(REPLACE(cf.custom_fields['[CC] - Tipo de Cliente'], 'cc_',''), 'er_', 'er'), 'serviços', 'serviço')
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
    t.ts_created,
    t.ts_created_local,
    t.ts_updated,
    t.ts_updated_local,
    t.year,
    t.month,
    t.day
FROM
    last_updated_ticket te
INNER JOIN
    union_historical_chat_with_zendesk t
        ON te.id_ticket = t.id_ticket
        AND te.ts_last_updated = t.ts_updated
LEFT JOIN
    distinct_groups g
        ON t.id_group = g.id_group
LEFT JOIN
    datalake_zendesk_custom_fields.custom_fields cf
        ON te.id_ticket = cf.id_ticket