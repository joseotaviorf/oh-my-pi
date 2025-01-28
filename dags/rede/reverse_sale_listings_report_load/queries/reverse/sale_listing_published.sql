SELECT
    UUID() AS id,
    CAST(
        (
            100000 * ROUND(fls.sk_sale_listing / 1000) +
            1000 * COUNT(*) OVER (
                PARTITION BY fls.sk_sale_listing 
                ORDER BY fls.ts_status_started 
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) + 
            3
        ) AS STRING
    ) AS business_id,
    fls.sk_region AS location_id,
    ROUND(fls.sk_sale_listing / 1000) AS property_id,
    COALESCE(dc.uuid_company, '1P') AS company_uuid,
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
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY fls.sk_sale_listing, dc.uuid_company ORDER BY fls.ts_status_started) = 1
    AND DATE(fls.ts_status_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')