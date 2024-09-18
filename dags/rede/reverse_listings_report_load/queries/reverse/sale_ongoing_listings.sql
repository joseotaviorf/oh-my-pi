SELECT
    CONCAT(
        SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 1, 8), '-',
        SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 9, 4), '-',
        SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 13, 4), '-',
        SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 17, 4), '-',
        SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 21, 12)
    ) AS id,
    sk_region AS location_id,
    dc.uuid_company AS company_uuid,
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
    dc.uuid_company IS NOT NULL
    AND fdol.year = {year}
    AND fdol.month = {month}
    AND fdol.day = {day}
GROUP BY
    fdol.sk_snapshot_date,
    fdol.sk_region,
    dc.uuid_company,
    fdol.year,
    fdol.month,
    fdol.day