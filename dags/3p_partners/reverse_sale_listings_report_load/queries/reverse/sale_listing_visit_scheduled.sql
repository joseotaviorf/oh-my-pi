SELECT
    UUID() AS id,
    CAST(fv.sk_booking AS STRING) AS business_id,
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
    dw_public.dim_company_3p_partners AS dc
      ON fv.sk_company_supply = dc.sk_company
JOIN
    dw_public.dim_date AS dd
      ON fv.sk_booking_created_date = dd.sk_date
WHERE
    MAKE_DATE(dd.year, dd.month, dd.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')