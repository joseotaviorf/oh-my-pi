SELECT
    dd.week_start AS dt_week_started,
    COUNT(DISTINCT CASE WHEN dhl.ts_publication IS NOT NULL THEN dhl.sk_house_listing ELSE NULL END) AS listings,
    COUNT(DISTINCT CASE WHEN rf.days_house_listing_to_contract_signed <= 56 THEN rf.sk_house_listing ELSE NULL END) AS listings_rented_8w,
    COUNT(DISTINCT CASE WHEN rf.days_house_listing_to_contract_signed <= 56 THEN rf.sk_house_listing ELSE NULL END)/CAST(COUNT(DISTINCT CASE WHEN dhl.ts_publication IS NOT NULL THEN dhl.sk_house_listing ELSE NULL END) AS DOUBLE) AS l2r_8w
FROM
    dw_rent.dim_house_listing AS dhl
LEFT JOIN
    dw_rent.fact_listing_rent_flows AS rf
        ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN
    dw_public.dim_date AS dd
        ON dd.date = dhl.ts_publication
WHERE
    dd.date >= DATE('2019-01-01')
    AND dd.date < DATE_ADD(CURRENT_DATE, -56)
    AND (dhl.country_code = 'BR' OR dhl.country_code = 'Undefined')
GROUP BY 1
ORDER BY 1 DESC
