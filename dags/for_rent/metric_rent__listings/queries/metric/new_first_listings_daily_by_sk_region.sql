SELECT
    dd.date AS first_listing_date,
    lf.sk_region,
    lf.country_code,
    COUNT(DISTINCT lf.sk_house_listing) AS new_first_listings
FROM 
    dw_public.fact_house_listing_flows AS lf
JOIN 
    dw_public.dim_date AS dd
        ON lf.sk_first_listing_date = dd.sk_date
        AND dd.date < current_date
WHERE 
    lf.sk_first_listing_date > 0
GROUP BY 1, 2, 3