SELECT
    UUID() AS id,
    CAST(MIN(fdol.sk_snapshot) AS STRING) AS business_id,
    sk_region AS location_id,
    COALESCE(dc.uuid_company, '1P') AS company_uuid,
    'SALE' AS business_context,
    COUNT(*) AS ongoing_listings_count,
    MAKE_DATE(fdol.year, fdol.month, fdol.day)::TIMESTAMP AS ts_event,
    fdol.year,
    fdol.month,
    fdol.day
FROM
    dw_sale.fact_daily_ongoing_listing AS fdol
JOIN
    dw_rede.dim_company AS dc
        ON dc.sk_company = fdol.sk_company
WHERE
    MAKE_DATE(fdol.year, fdol.month, fdol.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY
    fdol.sk_snapshot_date,
    fdol.sk_region,
    dc.uuid_company,
    fdol.year,
    fdol.month,
    fdol.day