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
last_updated_ticket as (
    SELECT
        id_ticket,
        MAX(ts_updated) AS ts_last_updated
    FROM
        tickets_filter
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
)
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
    g.name AS group_name,
    t.priority,
    t.recipient,
    t.tags,
    t.status,
    COALESCE(CAST(t.is_public AS BOOLEAN), FALSE) AS has_public_comments,
    CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.score') AS STRING) AS score,
    CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.reason') AS STRING) AS reason,
    CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.comment') AS STRING) AS comment,
    TO_JSON(cf.custom_fields) AS custom_fields,
    cf.custom_fields['Tipo de Solicitação'] AS request_type,
    cf.custom_fields['Tipo de Cliente'] AS client_type,
    cf.custom_fields['Cliente Tag'] AS customer_type_tag,
    cf.custom_fields['Motivo Tag'] AS contact_motivation_tag,
    cf.custom_fields['Assunto Tag'] AS contact_theme_tag,
    t.ts_created,
    t.ts_created_local,
    t.ts_updated,
    FROM_UTC_TIMESTAMP(t.ts_updated, 'Brazil/East') AS ts_updated_local,
    YEAR(t.ts_updated) AS year,
    MONTH(t.ts_updated) AS month,
    DAY(t.ts_updated) AS day
FROM
    last_updated_ticket te
INNER JOIN
    tickets_filter t
        ON te.id_ticket = t.id_ticket
        AND te.ts_last_updated = t.ts_updated
LEFT JOIN
    distinct_groups g
        ON t.id_group = g.id_group
LEFT JOIN
    datalake_zendesk_custom_fields.custom_fields cf
        ON t.id_ticket = cf.id_ticket
