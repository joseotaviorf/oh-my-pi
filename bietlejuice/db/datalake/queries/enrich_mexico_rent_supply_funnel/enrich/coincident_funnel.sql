WITH leads AS (
    SELECT
        country_code,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        COUNT(ts_lead) AS leads,
        NULL AS prospects,
        NULL AS qualifieds,
        NULL AS opportunities,
        NULL AS first_listings,
        DATE(DATE_TRUNC('month', ts_lead)) AS dt_month_started,
        DATE(DATE_TRUNC('week', ts_lead)) AS dt_week_started
    FROM
        datalake_mexico_rent_supply_funnel.listing_flow
    GROUP BY 1, 2, 3, 4, 5, 11, 12
),
prospects AS (
    SELECT
        country_code,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        NULL AS leads,
        COUNT(ts_prospect) AS prospects,
        NULL AS qualifieds,
        NULL AS opportunities,
        NULL AS first_listings,
        DATE(DATE_TRUNC('month', ts_prospect)) AS dt_month_started,
        DATE(DATE_TRUNC('week', ts_prospect)) AS dt_week_started
    FROM
        datalake_mexico_rent_supply_funnel.listing_flow
    WHERE
        ts_prospect IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 11, 12
),
qualifieds AS (
    SELECT
        country_code,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        NULL AS leads,
        NULL AS prospects,
        COUNT(ts_qualified) AS qualifieds,
        NULL AS opportunities,
        NULL AS first_listings,
        DATE(DATE_TRUNC('month', ts_qualified)) AS dt_month_started,
        DATE(DATE_TRUNC('week', ts_qualified)) AS dt_week_started
    FROM
        datalake_mexico_rent_supply_funnel.listing_flow
    WHERE
        ts_qualified IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 11, 12
),
opportunities AS (
    SELECT
        country_code,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        NULL AS leads,
        NULL AS prospects,
        NULL AS qualifieds,
        COUNT(DISTINCT id_house_listing) AS opportunities,
        NULL AS first_listings,
        DATE(DATE_TRUNC('month', ts_opportunity)) AS dt_month_started,
        DATE(DATE_TRUNC('week', ts_opportunity)) AS dt_week_started
    FROM
        datalake_mexico_rent_supply_funnel.listing_flow
    WHERE
        ts_opportunity IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 11, 12
),
first_listings AS (
    SELECT
        country_code,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        NULL AS leads,
        NULL AS prospects,
        NULL AS qualifieds,
        NULL AS opportunities,
        COUNT(DISTINCT id_house_listing) AS first_listings,
        DATE(DATE_TRUNC('month', ts_first_listing)) AS dt_month_started,
        DATE(DATE_TRUNC('week', ts_first_listing)) AS dt_week_started
    FROM
        datalake_mexico_rent_supply_funnel.listing_flow
    WHERE
        ts_first_listing IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 11, 12
),
union_all AS (
    SELECT *
    FROM
        leads
    UNION ALL
    SELECT *
    FROM
        prospects
    UNION ALL
    SELECT *
    FROM
        qualifieds
    UNION ALL
    SELECT *
    FROM
        opportunities
    UNION ALL
    SELECT *
    FROM
        first_listings
)
SELECT
    country_code,
    city_group,
    supply_mkt_origin, 
    supply_mkt_origin_detailed,
    mexico_channel,
    SUM(COALESCE(leads, 0)) AS leads,
    SUM(COALESCE(prospects, 0)) AS prospects,
    SUM(COALESCE(qualifieds, 0)) AS qualifieds,
    SUM(COALESCE(opportunities, 0)) AS opportunities,
    SUM(COALESCE(first_listings, 0)) AS first_listings,
    dt_week_started,
    dt_month_started
FROM
    union_all
GROUP BY 1, 2, 3, 4, 5, 11, 12