SELECT
    CAST(
        CONCAT(
            SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 1, 8), '-',
            SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 9, 4), '-',
            SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 13, 4), '-',
            SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 17, 4), '-',
            SUBSTRING(MD5(CAST(MIN(fdol.sk_snapshot) AS STRING)), 21, 12)
        ) AS STRING
    ) AS id,
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
    fdol.year = {year}
    AND fdol.month = {month}
    AND fdol.day = {day}
GROUP BY
    fdol.sk_snapshot_date,
    fdol.sk_region,
    dc.uuid_company,
    fdol.year,
    fdol.month,
    fdol.day