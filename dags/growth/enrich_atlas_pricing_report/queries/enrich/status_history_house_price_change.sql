SELECT DISTINCT
  bl.id_house,
  CASE
    WHEN business_context = 'RENT' THEN SUBSTRING(p_rent.sk_house_listing,10,12)
    WHEN business_context = 'SALE' THEN SUBSTRING(fl.sk_sale_listing,10,12)
  END AS version,
  UPPER(bl.business_context) AS business_context,
  'PRICE_CHANGE' AS status,
  'NA' AS status_reason,
  CASE
    WHEN business_context = 'RENT' THEN p_rent.rent
    WHEN business_context = 'SALE' THEN p_sale.price
  END AS price,
  CASE
    WHEN business_context = 'RENT' THEN p_rent.ts_price_started
    WHEN business_context = 'SALE' THEN dd.date
  END AS ts_status_started
FROM
  datalake_ebdb_clean.listing_business_context AS bl
LEFT JOIN
  dw_quintoandar.fact_listing_price_changes AS p_rent
    ON bl.id_house = SUBSTRING(p_rent.sk_house_listing,0,9)
LEFT JOIN
  dw_sale.fact_listing_price_changes AS p_sale
    ON p_sale.sk_house = bl.id_house
LEFT JOIN
  dw_public.dim_date AS dd
    ON p_sale.sk_price_started_date = dd.sk_date
LEFT JOIN
  dw_sale.fact_listings AS fl
    ON fl.sk_house = p_sale.sk_house
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) > 1
