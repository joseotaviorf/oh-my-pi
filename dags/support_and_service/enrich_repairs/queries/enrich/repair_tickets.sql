WITH distinct_groups AS (
    SELECT DISTINCT
        g.id_group,
        g.name
    FROM
        datalake_zendesk_tickets_clean.groups AS g
    WHERE
        LOWER(g.name) LIKE "%reparo%"
)
SELECT DISTINCT
    t.id_ticket,
    rr.id AS id_repair_request,
    tfm.id_contract,
    t.id_assignee,
    t.id_group,
    t.status,
    tfm.replies,
    SPLIT(REPLACE(REPLACE(REPLACE(t.tags, '[', ''), ']', ''), '"', ''), ',') AS tags,
    CASE
        WHEN GET_JSON_OBJECT(t.via, '$.channel') IN ('api', 'web')
            AND (
                t.tags LIKE '%call_contato_ativo%'
                OR t.tags LIKE '%call_contato_receptivo%'
            )
            THEN 'call'
        WHEN GET_JSON_OBJECT(t.via, '$.channel') IN ('api')
            AND t.tags LIKE '%form%'
            THEN 'form_faq'
        WHEN GET_JSON_OBJECT(t.via, '$.channel') IN ('web', 'email', 'chat', 'whatsapp')
            THEN GET_JSON_OBJECT(t.via, '$.channel')
        ELSE 'other'
    END AS channel,
    tfm.reopens,
    g.name AS group_name,
    GET_JSON_OBJECT(t.via, '$.channel') AS ticket_via,
    rr.service_provider,
    tfm.ts_solved,
    tfm.ts_solved_local,
    rr.ts_created AS ts_created_repair_request,
    t.ts_created,
    t.ts_created_local,
    t.ts_updated,
    FROM_UTC_TIMESTAMP(t.ts_updated, 'Brazil/East') AS ts_updated_local,
    t.year,
    t.month,
    t.day
FROM
    datalake_zendesk_tickets_clean.tickets_history AS t
INNER JOIN
    distinct_groups AS g
        ON t.id_group = g.id_group
LEFT JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
        ON tfm.id_ticket = t.id_ticket
LEFT JOIN
    datalake_repairs_clean.repair_request AS rr
        ON rr.id_third_party_crm_ticket_external = t.id_ticket
WHERE
    t.year = {year}
    AND t.month = {month}
    AND t.day = {day}