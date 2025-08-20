WITH visit AS (
    WITH visit_base AS (
        SELECT
            sk_core_visit AS sk_entity,
            id_visit AS id_entity,
            id_house,
            id_owner,
            id_visitor,
            id_agent,
            'VISIT' AS entity,
            business_context,
            CASE
                WHEN computed_status IN ('CANCELED', 'DONE', 'REQUEST_CANCELED', 'UNSUCCESSFUL') THEN FALSE
                WHEN computed_status IN ('CONFIRMED', 'REQUESTED') THEN TRUE
                WHEN computed_status IS NULL AND status IN ('Canceled', 'Done') THEN FALSE
                WHEN computed_status IS NULL AND status = 'Scheduled' THEN TRUE
                ELSE NULL
            END AS is_active,
            ts_created,
            ts_updated
        FROM
            core_visit.visit
    )
    SELECT
        sk_entity,
        id_entity,
        id_house,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
    UNION ALL
    SELECT
        sk_entity,
        id_entity,
        id_house,
        id_visitor AS id_user,
        entity,
        CASE
            WHEN business_context = 'RENT' THEN 'TENANT_PROSPECT'
            WHEN business_context = 'SALE' THEN 'BUYER_PROSPECT'
        END AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
    UNION ALL
    SELECT
        sk_entity,
        id_entity,
        id_house,
        id_agent AS id_user,
        entity,
        'AGENT_BROKER' AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
),
base AS (
    SELECT
        sk_entity,
        id_entity,
        id_house,
        CAST(NULL AS BIGINT) AS id_contract,
        id_user,
        entity,
        persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit
)
SELECT
    b.sk_entity,
    b.id_entity,
    b.id_house,
    b.id_contract,
    b.id_user,
    b.entity,
    b.persona,
    {house_address} AS house_address,
    b.is_active,
    b.ts_created,
    b.ts_updated
FROM
    base AS b
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = b.id_house