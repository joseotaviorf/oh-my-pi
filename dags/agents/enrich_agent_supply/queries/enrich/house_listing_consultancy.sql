WITH supply_attribution AS (
    SELECT
        scc.id_house,
        scc.id_agent,
        scc.id_user,
        scc.source,
        scc.agent_profile,
        scc.is_active,
        scc.ts_started,
        COALESCE(scc.ts_ended, NOW()) AS ts_ended,
        EXPLODE(SEQUENCE(DATE(scc.ts_started), DATE(COALESCE(scc.ts_ended, NOW())))) AS dt_reference
    FROM
        datalake_agent_supply.supply_conversion_consultancy AS scc
),
union_supply_attribution AS (
    SELECT
        hl.id_house_listing,
        hl.id_house,
        scc.id_agent,
        scc.id_user,
        scc.source,
        COALESCE(scc.agent_profile, "CORE") AS agent_profile,
        "RENT" AS business_context,
        scc.is_active,
        scc.ts_started,
        scc.ts_ended,
        hl.ts_first_publication,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing AS hl
    LEFT JOIN
        supply_attribution AS scc
            ON scc.id_house = hl.id_house
            AND scc.dt_reference BETWEEN DATE(hl.ts_listing_version_start) AND DATE(COALESCE(hl.ts_listing_version_end, NOW()))
            AND scc.ts_ended > hl.ts_listing_version_start
            AND scc.ts_started < COALESCE(hl.ts_listing_version_end, NOW())
    UNION
    SELECT
        sl.id_sale_listing AS id_house_listing,
        sl.id_house,
        scc.id_agent,
        scc.id_user,
        scc.source,
        COALESCE(scc.agent_profile, "CORE") AS agent_profile,
        "SALE" AS business_context,
        scc.is_active,
        scc.ts_started,
        scc.ts_ended,
        sl.ts_first_publication,
        CAST(NULL AS TIMESTAMP) AS ts_listing_version_start,
        CAST(NULL AS TIMESTAMP) AS ts_listing_version_end
    FROM
        datalake_sale_listings.sale_listing AS sl
    LEFT JOIN
        datalake_agent_supply.supply_conversion_consultancy AS scc
            ON scc.id_house = sl.id_house
)
SELECT
    sl.id_house_listing,
    sl.id_house,
    sl.id_agent,
    sl.id_user,
    sl.source,
    sl.agent_profile,
    sl.business_context,
    sl.is_active AS is_consultancy_active,
    ROW_NUMBER() OVER(PARTITION BY sl.id_house_listing, sl.business_context ORDER BY sl.is_active DESC, sl.ts_started DESC) = 1 AS is_lastest_on_listing,
    ROW_NUMBER() OVER(PARTITION BY sl.id_house_listing, sl.business_context ORDER BY sl.ts_started) = 1 AS is_first_on_listing,
    sl.ts_started,
    sl.ts_ended,
    sl.ts_first_publication,
    sl.ts_listing_version_start,
    sl.ts_listing_version_end
FROM
    union_supply_attribution AS sl
