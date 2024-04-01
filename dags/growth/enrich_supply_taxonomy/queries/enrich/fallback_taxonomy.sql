WITH registrant_user AS (
    SELECT 
        id_house,
        business_context,
        CASE 
            WHEN business_context = 'RENT' THEN user_listing_registrant_rent 
            WHEN business_context = 'SALE' THEN user_listing_registrant_sale
        END AS id_user_registrant,
        ts_first_listing
    FROM datalake_ebdb_listing.listing_business_context
),
fallback_lbc AS (
    SELECT 
        CAST(NULL AS BIGINT) AS id_lead,
        ce.id_house,
        ce.business_context,
        ce.id_user_registrant,
        3 AS source,
        IF(oa.id_user IS NOT NULL, 'owner_conversion', 'full_self_service') AS application,
        'FIRST_LISTING' AS funnel_step,
        CAST(NULL AS BIGINT) AS id_region,
        oa.ops_objective,
        oa.ops_agent,
        oa.ops_partner,
        CAST(NULL AS STRING) AS ops_approach,
        CAST(NULL AS STRING) AS ops_contact_medium,
        ce.ts_first_listing AS ts_event
    FROM registrant_user AS ce
    LEFT JOIN datalake_supply_flows.operations_agents AS oa
        ON (ce.id_user_registrant = oa.id_user)
),
fallback_opp AS (
    SELECT 
        CAST(NULL AS BIGINT) AS id_lead,
        ce.id_entity,
        ce.business_context,
        ce.id_user_registrant,
        4 AS source,
        'owner_conversion' AS application,
        ce.step AS funnel_step,
        CAST(NULL AS BIGINT) AS id_region,
        oa.ops_objective,
        oa.ops_agent,
        oa.ops_partner,
        CAST(NULL AS STRING) AS ops_approach,
        CAST(NULL AS STRING) AS ops_contact_medium,
        ce.ts_event_adjusted AS ts_event
    FROM datalake_supply_flows_migrate.conversion_events AS ce
    JOIN datalake_supply_flows.operations_agents AS oa
        ON (ce.id_user_registrant = oa.id_user)
    WHERE ce.step = 'OPPORTUNITY'
),
fallback_fl AS (
    SELECT 
        CAST(NULL AS BIGINT) AS id_lead,
        ce.id_entity,
        ce.business_context,
        ce.id_user_registrant,
        5 AS source,
        'owner_conversion' AS application,
        ce.step,
        CAST(NULL AS BIGINT) AS id_region,
        oa.ops_objective,
        oa.ops_agent,
        oa.ops_partner,
        CAST(NULL AS STRING) AS ops_approach,
        CAST(NULL AS STRING) AS ops_contact_medium,
        ce.ts_event_adjusted AS ts_event
    FROM datalake_supply_flows_migrate.conversion_events AS ce
    JOIN datalake_supply_flows.operations_agents AS oa
        ON (ce.id_user_registrant = oa.id_user)
    WHERE ce.step = 'FIRST_LISTING'
),
joined_tb AS (
    SELECT *
    FROM fallback_lbc
    UNION ALL
    SELECT *
    FROM fallback_opp
    UNION ALL
    SELECT *
    FROM fallback_fl
)

SELECT 
    *,
    NOW() AS ts_load,
    YEAR(ts_event) AS year,
    MONTH(ts_event) AS month,
    DAY(ts_event) AS day
FROM joined_tb
