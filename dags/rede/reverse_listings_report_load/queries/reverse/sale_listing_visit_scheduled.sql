SELECT
    CAST(fv.sk_booking * 1000 + 4 AS BIGINT) AS id,
    fv.sk_region AS location_id,
    fv.sk_house AS property_id,
    dc.uuid_company AS company_uuid,
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
    dc.uuid_company IS NOT NULL
    AND dd.year = {year}
    AND dd.month = {month}
    AND dd.day = {day}
