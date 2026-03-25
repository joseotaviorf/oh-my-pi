WITH visit_events AS (
    SELECT
        id_visit,
        event_type,
        ts_created
    FROM
        datalake_ebdb_clean.visit_status_log
    WHERE
        event_type IN ('VISIT_REQUESTED', 'VISIT_SCHEDULED', 'VISIT_CONFIRMED', 'VISIT_DONE',
            'VISIT_CANCELED', 'VISIT_UNSUCCESSFUL', 'VISIT_REGISTERED', 'VISIT_RESCHEDULED', 'VISIT_STALLED')
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY ts_created DESC) = 1
),
visit_base AS (
    SELECT
        v.code AS id_entity,
        v.id_house,
        CAST(NULL AS BIGINT) AS id_contract,
        v.id_owner,
        v.id_visitor,
        v.id_agent,
        'VISIT' AS entity,
        v.business_context,
        TO_JSON(
            STRUCT(
                ve.event_type AS what,
                v.ts_visit AS when
            )
        ) AS properties,
        CASE
            WHEN computed_status IN ('CANCELED', 'DONE', 'REQUEST_CANCELED', 'UNSUCCESSFUL', 'STALLED') THEN FALSE
            WHEN computed_status IN ('CONFIRMED', 'REQUESTED') THEN TRUE
            ELSE NULL
        END AS is_active,
        v.ts_created,
        v.ts_updated
    FROM
        core_visit.visit AS v
    INNER JOIN
        visit_events AS ve
            ON v.id_visit = ve.id_visit
    WHERE
        YEAR(v.ts_created) >= 2025
)
SELECT
    id_entity,
    id_house,
    id_contract,
    id_owner AS id_user,
    entity,
    'OWNER' AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    visit_base
UNION ALL
SELECT
    id_entity,
    id_house,
    id_contract,
    id_visitor AS id_user,
    entity,
    CASE
        WHEN business_context = 'RENT' THEN 'TENANT_PROSPECT'
        WHEN business_context = 'SALE' THEN 'BUYER_PROSPECT'
    END AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    visit_base
UNION ALL
SELECT
    id_entity,
    id_house,
    id_contract,
    id_agent AS id_user,
    entity,
    'AGENT_BROKER' AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    visit_base
WHERE
    id_agent IS NOT NULL
