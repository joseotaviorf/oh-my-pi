WITH visit AS (
    WITH visit_base AS (
        SELECT
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
    ),
    visit_filtered AS (
        SELECT *
        FROM
            visit_base
        WHERE
            is_active = TRUE 
            OR (
                is_active = FALSE 
                AND DATE(ts_updated) BETWEEN 
                 ADD_MONTHS(COALESCE(DATE('{load_start_date}'), CURRENT_DATE()), -3)
                 AND COALESCE(DATE('{load_end_date}'), CURRENT_DATE())
            )
            OR is_active IS NULL
    )
    SELECT
        id_entity,
        id_house,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_filtered
    UNION ALL
    SELECT
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
        visit_filtered
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_agent AS id_user,
        entity,
        'AGENT_BROKER' AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_filtered
    WHERE
        id_agent IS NOT NULL
),
offer AS (
    WITH offer_base AS (
        SELECT
            id_offer AS id_entity,
            id_house,
            id_tenant,
            id_owner,
            'OFFER' AS entity,
            CASE
                WHEN status = 'PROPOSED' THEN TRUE
                WHEN status IN ('ACCEPTED', 'DISMISSED', 'REJECTED') THEN FALSE
                ELSE NULL
            END AS is_active,
            ts_created,
            ts_updated
        FROM
            core_offer.offer
    ),
    offer_filtered AS (
        SELECT *
        FROM
            offer_base
        WHERE
            is_active = TRUE 
            OR (
                is_active = FALSE 
                AND DATE(ts_updated) BETWEEN 
                 ADD_MONTHS(COALESCE(DATE('{load_start_date}'), CURRENT_DATE()), -3)
                 AND COALESCE(DATE('{load_end_date}'), CURRENT_DATE())
            )
            OR is_active IS NULL
    )
    SELECT
        id_entity,
        id_house,
        id_tenant AS id_user,
        entity,
        'TENANT_PROSPECT' AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        offer_filtered
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        offer_filtered
),
contract AS (
    WITH contract_base AS (
        SELECT
            id_contract AS id_entity,
            id_house,
            id_contract,
            id_owner,
            id_tenant,
            'CONTRACT' AS entity,
            CASE
                WHEN status IN ('Cancelado', 'Finalizado') THEN FALSE
                WHEN status IN ('Ativo', 'Minuta', 'PreAssinaturas') THEN TRUE
                ELSE NULL
            END AS is_active,
            ts_signed,
            ts_created,
            ts_updated
        FROM
            core_contract.contract
    ),
    contract_filtered AS (
        SELECT *
        FROM
            contract_base
        WHERE
            is_active = TRUE 
            OR (
                is_active = FALSE 
                AND DATE(ts_updated) BETWEEN 
                 ADD_MONTHS(COALESCE(DATE('{load_start_date}'), CURRENT_DATE()), -3)
                 AND COALESCE(DATE('{load_end_date}'), CURRENT_DATE())
            )
            OR is_active IS NULL
    )
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract_filtered
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_tenant AS id_user,
        entity,
        CASE
            WHEN ts_signed IS NOT NULL THEN 'TENANT'
            ELSE 'TENANT_PROSPECT'
        END AS persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract_filtered
),
base AS (
    SELECT
        {sk_entity} AS sk_entity,
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
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
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
        offer
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract
)
SELECT
    b.sk_entity,
    b.id_entity,
    b.id_house,
    b.id_contract,
    b.id_user,
    u.uuid_person,
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
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = b.id_user
WHERE
    b.id_user IS NOT NULL
    AND b.persona IS NOT NULL