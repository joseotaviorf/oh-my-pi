SELECT
    UUID() AS id,
    CAST(MIN(fdol.sk_snapshot) AS STRING) AS business_id,
    sk_region AS location_id,
    COALESCE(cb.uuid_company, '1P') AS company_uuid,
    'SALE' AS business_context,
    COUNT(*) AS ongoing_listings_count,
    MAKE_DATE(fdol.year, fdol.month, fdol.day)::TIMESTAMP AS ts_event,
    fdol.year,
    fdol.month,
    fdol.day
FROM
    dw_sale.fact_daily_ongoing_listing AS fdol
JOIN
    core_brokers.brokers AS cb
    ON fdol.sk_broker = cb.sk_broker
WHERE
    MAKE_DATE(fdol.year, fdol.month, fdol.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY
    fdol.sk_snapshot_date,
    fdol.sk_region,
    cb.uuid_company,
    fdol.year,
    fdol.month,
    fdol.day