WITH old_origin AS (
    SELECT
        v.id AS id_visit,
        CASE
            WHEN vo.name = 'SelfServiceWeb' THEN 'TENANT_PWA'
            WHEN vo.name = 'Admin' THEN 'MAGIC_LINK'
            WHEN vo.name = 'Sistema' THEN 'SYSTEM'
            WHEN vo.name = 'Corretores' THEN 'AGENT_PWA'
            WHEN vo.name = 'Inquilinos' THEN 'TENANT_NATIVE'
            WHEN vo.name = 'Proprietarios' THEN 'OWNER_PWA'
            WHEN vo.name = 'Portfolio' THEN 'PORTFOLIO_MANAGER'
            WHEN vo.name = 'MagicLink' THEN 'MAGIC_LINK'
            WHEN vo.name = 'WhatsApp' THEN 'WHATSAPP'
            ELSE UPPER(name)
        END AS visit_request_channel,
        v.ts_created AS ts_visit_requested
    FROM
        datalake_ebdb_clean.visit AS v
    LEFT JOIN
        datalake_ebdb_clean.visit_origin AS vo
            ON v.id_creation_origin = vo.id
    WHERE
        DATE(v.ts_created) < '2024-11-01'
),
new_origin AS (
    SELECT
        vse.id_visit,
        MIN_BY(vse.channel, vse.ts_created) AS visit_request_channel,
        MIN_BY(vse.channel_unified, vse.ts_created) AS visit_request_channel_unified,
        MIN(vse.ts_created) AS ts_visit_requested
    FROM
        datalake_visit.visit_status_events AS vse
    JOIN
        datalake_ebdb_clean.visit AS v
            ON vse.id_visit = v.id
    WHERE
        vse.event_type = 'VISIT_REQUESTED'
        AND DATE(v.ts_created) >= '2024-11-01'
    GROUP BY 1
)
SELECT
    id_visit,
    visit_request_channel,
    visit_request_channel AS visit_request_channel_unified,
    ts_visit_requested
FROM
    old_origin
UNION ALL
SELECT
    id_visit,
    visit_request_channel,
    visit_request_channel_unified,
    ts_visit_requested
FROM
    new_origin
