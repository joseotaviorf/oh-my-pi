SELECT
    DATE_TRUNC('month', DATE(hl.ts_publication)) AS month,
    dr.country_code,
    COUNT(DISTINCT hl.sk_house_listing) AS total_listings
FROM
    dw_rent.dim_house_listing AS hl
LEFT JOIN
    dw_rent.fact_house_listings AS fhl
        ON fhl.sk_house_listing = hl.sk_house_listing
LEFT JOIN
    dw_public.dim_region AS dr
        ON dr.sk_region = fhl.sk_region
WHERE
    dr.city_group IS NOT NULL
    AND hl.version > 0
    AND hl.ts_publication IS NOT NULL
GROUP BY 1, 2
