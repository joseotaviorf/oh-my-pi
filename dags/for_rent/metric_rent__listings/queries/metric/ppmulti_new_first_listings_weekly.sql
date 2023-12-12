SELECT
    DATE_TRUNC('week', dd.date) AS week,
    lf.country_code,
    COUNT(DISTINCT lf.sk_house_listing) AS new_first_listings
FROM 
    dw_public.fact_house_listing_flows AS lf
JOIN 
    dw_public.dim_date AS dd
        ON lf.sk_first_listing_date = dd.sk_date
        AND DATE_TRUNC('week', dd.date) < DATE_TRUNC('week', CURRENT_DATE)
JOIN
    dw_public.fact_house_listings AS fhl
        ON lf.sk_house_listing = fhl.sk_house_listing
JOIN
    datalake_pro_owners.daily_owner_houses_quantity_history AS doh
        ON doh.id_owner = fhl.sk_owner
        AND dd.year = doh.year
        AND dd.month = doh.month
        AND dd.day = doh.day
WHERE 
    lf.sk_first_listing_date > 0
        AND doh.ongoing_houses >= 5
GROUP BY 1, 2