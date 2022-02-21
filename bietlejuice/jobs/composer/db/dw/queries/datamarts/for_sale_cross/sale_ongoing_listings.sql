WITH daily_published_listings AS (
SELECT
        f.sk_sale_listing,
        CASE WHEN hp.sk_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
        hp.partner AS supply_3p_partner,
        f.status_history,
        d.date,
        d.week_start,
        d.weekday_name,
        f.sk_status_start_date,
        f.sk_status_end_date,
        f.sk_region,
        ROW_NUMBER() OVER(PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS order_status -- daily order status
FROM 
    sale.fact_listing_status f
JOIN 
    dim_date d
        ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) 
        AND COALESCE(NULLIF(sk_status_end_date, -1), CAST(REPLACE(CAST(current_date AS VARCHAR), '-', '') AS BIGINT) - 1)
LEFT JOIN 
    datamarts.houses_3p AS hp
        ON f.sk_sale_listing / 1000 = hp.sk_house
WHERE 
    f.status_history = 'PUBLISHED'
), 

ciq AS (
SELECT
    sk_house_listing, 
    sk_quintoandar_consultant,
    type_big_agent,
    businesscontext
FROM 
    datamarts.quintoandar_consultant_listings 
WHERE 
    businesscontext = 'SALE'
),

daily_published_listings_with_region AS (
SELECT
    fhs.sk_sale_listing,
    ciq.sk_house_listing AS ciq_assignment,
    fhs.date,
    fhs.week_start,
    fhs.weekday_name,
    fhs.order_status,
    fhs.status_history,
    dr.sk_region,
    fhs.supply_3p_partner,
    fhs.is_3p_supply,
    dr.name AS region,
    dr.city_name,
    dr.city_group
FROM 
    daily_published_listings fhs
JOIN 
    dim_region dr
        ON dr.sk_region = fhs.sk_region
LEFT JOIN 
    ciq
        ON ciq.sk_house_listing = fhs.sk_sale_listing
WHERE 
    fhs.order_status = 1
)

SELECT
    DATE,
    weekday_name,
    week_start,
    sk_region,
    region,
    city_name,
    city_group,
    supply_3p_partner,
    is_3p_supply,
    COUNT(DISTINCT sk_sale_listing) AS ongoing_listings,
    COUNT(DISTINCT ciq_assignment) AS ciq_listing
FROM 
    daily_published_listings_with_region
GROUP BY 
    1, 
    2, 
    3, 
    4,
    5, 
    6, 
    7,
    8,
    9
ORDER BY 
    1