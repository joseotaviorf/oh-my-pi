SELECT
    CAST(
        CONCAT(
            SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 1, 8), '-',
            SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 9, 4), '-',
            SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 13, 4), '-',
            SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 17, 4), '-',
            SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 21, 12)
        ) AS STRING
    ) AS id,
    fv.sk_region AS location_id,
    fv.sk_house AS property_id,
    COALESCE(dc.uuid_company, '1P') AS company_uuid,
    'SALE' AS business_context,
    fv.ts_booking_created AS ts_event,
    dd.year,
    dd.month,
    dd.day
FROM
    dw_sale.fact_visits AS fv
JOIN
    dw_rede.dim_company AS dc
      ON fv.sk_company_supply = dc.sk_company
JOIN
    dw_public.dim_date AS dd
      ON fv.sk_booking_created_date = dd.sk_date
WHERE
    dd.year = {year}
    AND dd.month = {month}
    AND dd.day = {day}