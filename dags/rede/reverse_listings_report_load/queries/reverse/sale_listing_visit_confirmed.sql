SELECT
    CONCAT(
        SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 1, 8), '-',
        SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 9, 4), '-',
        SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 13, 4), '-',
        SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 17, 4), '-',
        SUBSTRING(MD5(CAST(fv.sk_booking AS STRING)), 21, 12)
    ) AS id,
    fv.sk_region AS location_id,
    fv.sk_house AS property_id,
    dc.uuid_company AS company_uuid,
    'SALE' AS business_context,
    IF(fv.ts_visit_completed IS NOT NULL, fv.ts_visit_follow_up, NULL) AS ts_event,
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
      ON fv.sk_visit_follow_up_date = dd.sk_date
WHERE
    fv.ts_visit_completed IS NOT NULL
    AND dc.uuid_company IS NOT NULL
    AND dd.year = {year}
    AND dd.month = {month}
    AND dd.day = {day}
