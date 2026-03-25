WITH base AS (
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_visit_entities_views.visit
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_for_rent_entities_views.offer
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_for_rent_entities_views.contract
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_for_rent_entities_views.termination
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_listing_entities_views.listing
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_for_rent_entities_views.inspection
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_for_rent_entities_views.credit_evaluation
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_for_rent_entities_views.onboarding
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_growth_entities_views.photo_session
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_for_rent_entities_views.reservation
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_for_rent_entities_views.repair
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_fintech_entities_views.invoice
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_growth_entities_views.house_draft
)
SELECT
    b.sk_entity,
    CAST(b.id_entity AS STRING) AS id_entity,
    CAST(b.id_house AS STRING) AS id_house,
    CAST(b.id_contract AS STRING) AS id_contract,
    CAST(b.id_user AS STRING) AS id_user,
    u.uuid_person,
    b.entity,
    b.persona,
    b.business_context,
    b.properties,
    {house_address} AS house_address,
    b.is_active,
    CASE
        WHEN b.is_active = FALSE THEN b.ts_updated
        ELSE NULL
    END AS ts_inactive,
    b.ts_created,
    b.ts_updated
FROM
    base AS b
LEFT JOIN
    core_house.house AS h
        ON h.id_house = b.id_house
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = b.id_user
WHERE
    b.id_user IS NOT NULL
    AND b.persona IS NOT NULL
