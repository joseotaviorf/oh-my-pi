WITH leads AS (
    SELECT
        DATE_TRUNC('month', TO_DATE(CAST(sk_lead_date AS STRING), 'yyyymmdd')) AS month_start,
        DATE_TRUNC('week', TO_DATE(CAST(sk_lead_date AS STRING),'yyyymmdd')) AS week_start,
	country_name,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        COUNT(sk_lead_date) AS leads,
        NULL AS prospects,
        NULL AS qualifieds,
        NULL AS opportunities,
        NULL AS first_listings
    FROM
        reverse_navent_bigquery.mexico_supply_funnel
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),
prospects AS (
    SELECT
        DATE_TRUNC('month', TO_DATE(CAST(sk_prospect_date AS STRING),'yyyymmdd')) AS month_start,
        DATE_TRUNC('week', TO_DATE(CAST(sk_prospect_date AS STRING),'yyyymmdd')) AS week_start,
        country_name,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        NULL AS leads,
        COUNT(sk_prospect_date) AS prospects,
        NULL AS qualifieds,
        NULL AS opportunities,
        NULL AS first_listings
    FROM
        reverse_navent_bigquery.mexico_supply_funnel
    WHERE
        sk_prospect_date > 0
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),
qualifieds AS (
    SELECT
        DATE_TRUNC('month', TO_DATE(CAST(sk_qualified_date AS STRING),'yyyymmdd')) AS month_start,
        DATE_TRUNC('week', TO_DATE(CAST(sk_qualified_date AS STRING),'yyyymmdd')) AS week_start,
        country_name,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        NULL AS leads,
        NULL AS prospects,
        COUNT(sk_qualified_date) AS qualifieds,
        NULL AS opportunities,
        NULL AS first_listings
    FROM
        reverse_navent_bigquery.mexico_supply_funnel
    WHERE
        sk_qualified_date > 0
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),
opportunities AS (
    SELECT
        DATE_TRUNC('month', TO_DATE(CAST(sk_opportunity_date AS STRING),'yyyymmdd')) AS month_start,
        DATE_TRUNC('week', TO_DATE(CAST(sk_opportunity_date AS STRING),'yyyymmdd')) AS week_start,
        country_name,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        NULL AS leads,
        NULL AS prospects,
        NULL AS qualifieds,
        COUNT(DISTINCT sk_house_listing) AS opportunities,
        NULL AS first_listings
    FROM
        reverse_navent_bigquery.mexico_supply_funnel
    WHERE
        sk_opportunity_date > 0
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),
first_listings AS (
    SELECT
        DATE_TRUNC('month', TO_DATE(CAST(sk_first_listing_date AS STRING),'yyyymmdd')) AS month_start,
        DATE_TRUNC('week', TO_DATE(CAST(sk_first_listing_date AS STRING),'yyyymmdd')) AS week_start,
        country_name,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        NULL AS leads,
        NULL AS prospects,
        NULL AS qualifieds,
        NULL AS opportunities,
        COUNT(DISTINCT sk_house_listing) AS first_listings
    FROM
        reverse_navent_bigquery.mexico_supply_funnel
    WHERE
        sk_first_listing_date > 0
    GROUP BY 1, 2, 3, 4, 5, 6, 7
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
    country_name,
    city_group,
    supply_mkt_origin, 
    supply_mkt_origin_detailed,
    mexico_channel,
    SUM(COALESCE(leads, 0)) AS leads,
    SUM(COALESCE(prospects, 0)) AS prospects,
    SUM(COALESCE(qualifieds, 0)) AS qualifieds,
    SUM(COALESCE(opportunities, 0)) AS opportunities,
    SUM(COALESCE(first_listings, 0)) AS first_listings,
    DATE(month_start) AS dt_month_started,
    DATE(week_start) AS dt_week_started,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    union_all
GROUP BY 1, 2, 3, 4, 5, 11, 12, 13, 14, 15