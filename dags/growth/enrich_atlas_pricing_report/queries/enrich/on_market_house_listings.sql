SELECT
  lbc.id_house,
  h.id_region,
  lbc.business_context,
  dr.name AS neighborhood,
  dr.city_name AS city,
  dr.region_code,
  CASE
    WHEN LOWER(h.type) IN ('apartamento', 'studiooukitchenette') THEN 'apartamento'
    WHEN LOWER(h.type) IN ('casa', 'casacondominio') THEN 'casa'
  END AS house_type,
  'on-market' AS house_status,
  CASE
    WHEN lbc.business_context = 'RENT' THEN h.rent
    WHEN lbc.business_context = 'SALE' THEN h.sale_price
  END AS price,
  CASE
    WHEN lbc.business_context = 'RENT' THEN h.total_value
  END AS rent_total_value,
  CASE
    WHEN lbc.business_context = 'SALE' THEN h.sale_price/h.total_area
  END AS sale_price_m2,
  CASE WHEN h.condo_type = 'Normal' THEN h.condo END AS condo,
  CASE WHEN h.iptu_type = 'Normal' THEN h.iptu END AS iptu,
  pred.p_10 AS calculator_min_price,
  pred.p_90 AS calculator_max_price,
  DATE_DIFF(CURRENT_DATE(), lbc.ts_last_publication) AS days_in_the_market,
  h.lat,
  h.lng,
  h.bedrooms,
  h.total_area
FROM
  datalake_ebdb_clean.listing_business_context AS lbc
INNER JOIN
  datalake_ebdb_clean.house AS h
    ON h.id = lbc.id_house
INNER JOIN
  dw_public.dim_region AS dr
    ON h.id_region = dr.sk_region
LEFT JOIN
  datalake_ebdb_clean.house_predicted_price AS pred
    ON lbc.id_house = pred.id_house
    AND lbc.business_context = pred.business_context
WHERE
  lbc.status = 'PUBLISHED'
