SELECT
    CAST((
            100000 * ROUND(fls.sk_sale_listing / 1000) +
            1000 * COUNT(*) OVER(PARTITION BY fls.sk_sale_listing ORDER BY fls.ts_status_started ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) + 
            3
        ) AS BIGINT) AS id,
    fls.sk_region AS location_id,
    ROUND(fls.sk_sale_listing / 1000) AS property_id,
    dc.uuid_company AS company_uuid,
    'SALE' AS business_context,
    fls.ts_status_started AS ts_event,
    YEAR(fls.ts_status_started) AS year,
    MONTH(fls.ts_status_started) AS month,
    DAY(fls.ts_status_started) AS day
FROM
    dw_sale.fact_listing_status AS fls
JOIN
    dw_rede.dim_company AS dc
        ON dc.sk_company = fls.sk_company
WHERE
    status_history = 'PUBLISHED'
    AND dc.uuid_company IS NOT NULL
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY fls.sk_sale_listing, dc.uuid_company ORDER BY fls.ts_status_started) = 1
    AND year = {year}
    AND month = {month}
    AND day = {day}
