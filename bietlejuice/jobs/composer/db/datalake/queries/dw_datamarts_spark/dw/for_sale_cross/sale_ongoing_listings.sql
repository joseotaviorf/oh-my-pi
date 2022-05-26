WITH daily_published_listings AS (
    SELECT
        f.sk_sale_listing,
        CASE 
            WHEN hp.id_house IS NOT NULL THEN 1 
            ELSE 0 
        END AS is_3p_supply,
        hp.partner AS supply_3p_partner,
        f.status_history,
        d.date,
        d.week_start,
        d.weekday_name,
        f.sk_status_start_date,
        f.sk_status_end_date,
        f.sk_region,
        ROW_NUMBER() OVER(PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS order_status
    FROM 
        dw_sale.fact_listing_status AS f
    JOIN 
        dw_public.dim_date AS d
            ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) 
            AND COALESCE(NULLIF(sk_status_end_date, -1), CAST(REPLACE(CAST(current_date AS STRING), '-', '') AS BIGINT) - 1)
    LEFT JOIN 
        datalake_3p.houses_3p AS hp
            ON CAST(SUBSTR(CAST(f.sk_sale_listing AS STRING), 1, 9) AS BIGINT) = hp.id_house
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
        dw_datamarts_cross.quintoandar_consultant_listings
    WHERE 
        businesscontext = 'SALE'
        AND (type_big_agent='CIQ_FULL' OR type_big_agent='CIQ_MANAGER' AND dt_sale > dt_ciq_started)
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
        daily_published_listings AS fhs
    JOIN 
        dw_public.dim_region AS dr
            ON dr.sk_region = fhs.sk_region
    LEFT JOIN 
        ciq
            ON ciq.sk_house_listing = fhs.sk_sale_listing
    WHERE 
        fhs.order_status = 1
)
SELECT
    date,
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
    1, 2, 3, 4, 5, 6, 7, 8, 9
ORDER BY 
    1
