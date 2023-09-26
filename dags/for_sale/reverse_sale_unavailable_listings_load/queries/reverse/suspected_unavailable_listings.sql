WITH listings_1p AS (
    SELECT 
        sk_house,
        sk_region, 
        CAST(ts_first_publication AS DATE) dt_first_publication,
        CAST(ts_last_publication AS DATE)  AS dt_last_quintoandar_publication
    FROM 
        dw_sale.fact_listings
    INNER JOIN 
        dw_sale.dim_listing
          USING(sk_house)
    WHERE
        is_3p_supply = FALSE
        AND status = 'PUBLISHED'
),
listings_3p AS (
    SELECT 
        sk_house,
        sk_region,
        CAST(ts_house_created AS DATE) AS dt_first_publication,
        CAST(ts_last_publication AS DATE) AS dt_last_quintoandar_publication
    FROM 
        dw_rede.dim_lead_3p
    INNER JOIN 
        dw_rede.fact_lead_3p_flows
            USING(sk_lead_3p)
    INNER JOIN 
        dw_rede.dim_lead_3p_context
            USING(sk_lead_3p_context)
    INNER JOIN 
        dw_sale.dim_listing
            USING(sk_house)
    WHERE 
        status = 'PUBLISHED' 
        AND business_context = 'SALE'
),
published_listings AS (
    SELECT
        sk_house,
        sk_region,
        dt_first_publication,
        dt_last_quintoandar_publication
    FROM 
        listings_1p
    UNION ALL 
    SELECT 
        sk_house,
        sk_region,
        dt_first_publication,
        dt_last_quintoandar_publication
    FROM
        listings_3p
), 
listings_without_bookings AS (
    SELECT
        sk_house, 
        COUNT(DISTINCT sk_house) AS vbs_last_30_days
    FROM 
        dw_sale.fact_visits
    WHERE 
        ts_booking_created >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY 
        1
),
suspected_unavailability_listings AS (
    SELECT 
        id_house,
        contact_attempts,
        is_confirmed
    FROM 
        datalake_ebdb_clean.suspected_unavailability_listings
    WHERE 
        ts_last_contact_attempt >= CURRENT_DATE - INTERVAL '30 DAYS'
),
suspected_unavailable_listings AS (
    SELECT DISTINCT
        ol.sk_house,
        dt_last_quintoandar_publication
    FROM 
        published_listings AS ol
    LEFT JOIN 
        listings_without_bookings
            USING(sk_house)
    LEFT JOIN 
        dw_public.dim_region
            USING(sk_region)
    LEFT JOIN 
        suspected_unavailability_listings AS sl 
            ON sl.id_house = ol.sk_house
    WHERE 
        country_code = 'BR'
        AND DATEDIFF(CURRENT_DATE,dt_last_quintoandar_publication) >= 30
        AND DATEDIFF(CURRENT_DATE,dt_first_publication) >= 120
        AND vbs_last_30_days IS NULL
        AND (sl.is_confirmed IS NULL OR sl.is_confirmed = FALSE) -- If the house is not confirmed as available
        AND (sl.contact_attempts IS NULL OR sl.contact_attempts < 3) -- Can't have received this HSM more than twice and not replied to it
),
dispatch_rules (
    SELECT 
        sk_house,
        MOD(DATEDIFF(CAST(CURRENT_DATE AS DATE), CAST(dt_last_quintoandar_publication AS DATE)), 30) = 0 AS need_to_check_available
    FROM 
        suspected_unavailable_listings
)
SELECT 
    sk_house,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM 
    dispatch_rules 
WHERE
    need_to_check_available = TRUE
LIMIT 
    1000