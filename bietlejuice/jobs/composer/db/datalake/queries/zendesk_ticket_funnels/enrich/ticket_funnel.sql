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
),
last_updated_ticket_field AS (
    SELECT
        id_ticket_fields,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_zendesk_tickets_clean.ticket_fields
    GROUP BY 1
),
distinct_ticket_fields AS (
    SELECT
        cf.id_ticket_fields,
        cf.raw_title
    FROM
        datalake_zendesk_tickets_clean.ticket_fields cf
    INNER JOIN
        last_updated_ticket_field ltf
            ON cf.id_ticket_fields=ltf.id_ticket_fields
            AND cf.ts_updated=ltf.ts_last_updated
    GROUP BY 1, 2
),
transformed_custom_fields AS (
    SELECT
        cf.id_ticket,
        cf.custom_fields,
        tf.raw_title,
        cf.value_field
    FROM
        datalake_zendesk_custom_fields.custom_fields cf
    INNER JOIN
        distinct_ticket_fields tf
            ON REPLACE(cf.id_field, '"', '') = tf.id_ticket_fields
    WHERE
        tf.raw_title IN ('Tipo de Solicitação', 'Tipo de Cliente', 'Cliente Tag', 'Motivo Tag', 'Assunto Tag')
    GROUP BY 1, 2, 3, 4
)
SELECT
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
    tcf1.custom_fields,
    CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.score') AS STRING) AS score,
    CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.reason') AS STRING) AS reason,
    CAST(GET_JSON_OBJECT(t.satisfaction_rating,'$.comment') AS STRING) AS comment,
    tcf1.value_field AS request_type,
    tcf2.value_field AS client_type,
    tcf3.value_field AS customer_type_tag,
    tcf4.value_field AS contact_motivation_tag,
    tcf5.value_field AS contact_theme_tag,
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
    transformed_custom_fields tcf1
        ON t.id_ticket = tcf1.id_ticket
        AND tcf1.raw_title = 'Tipo de Solicitação'
LEFT JOIN
    transformed_custom_fields tcf2
        ON t.id_ticket = tcf2.id_ticket
        AND tcf2.raw_title = 'Tipo de Cliente'
LEFT JOIN
    transformed_custom_fields tcf3
        ON t.id_ticket = tcf3.id_ticket
        AND tcf3.raw_title = 'Cliente Tag'
LEFT JOIN
    transformed_custom_fields tcf4
        ON t.id_ticket = tcf4.id_ticket
        AND tcf4.raw_title = 'Motivo Tag'
LEFT JOIN
    transformed_custom_fields tcf5
        ON t.id_ticket = tcf5.id_ticket
        AND tcf5.raw_title = 'Assunto Tag'
