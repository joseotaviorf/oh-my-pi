SELECT
    DATE_TRUNC('week', dd.date) AS week,
    lf.country_code,
    COUNT(DISTINCT lf.sk_house_listing) AS new_first_listings
FROM 
    dw_public.fact_house_listing_flows AS lf
JOIN 
    dw_public.dim_date dd
        ON lf.sk_first_listing_date = dd.sk_date
        AND DATE_TRUNC('week', dd.date) < DATE_TRUNC('week', CURRENT_DATE)
WHERE 
    lf.sk_first_listing_date > 0
GROUP BY 1, 2