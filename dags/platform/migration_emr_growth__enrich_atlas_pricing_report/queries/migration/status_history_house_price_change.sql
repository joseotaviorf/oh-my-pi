SELECT
  bl.id_house,
  UPPER(bl.business_context) AS business_context,
  'PRICE_CHANGE' AS status,
  ROUND(p_rent.rent, 2) AS price,
  p_rent.ts_price_started,
  p_rent.ts_price_ended
FROM
  datalake_ebdb_clean.listing_business_context AS bl
INNER JOIN
  dw_quintoandar.fact_listing_price_changes AS p_rent
    ON bl.id_house = SUBSTRING(p_rent.sk_house_listing,0,9)
      AND bl.business_context = 'RENT'
      AND SUBSTRING(CAST(p_rent.sk_house_listing AS STRING),10) > '000'
UNION ALL
SELECT
  bl.id_house,
  UPPER(bl.business_context) AS business_context,
  'PRICE_CHANGE' AS status,
  ROUND(p_sale.sale_price, 2) AS price,
  p_sale.ts_price_started,
  p_sale.ts_price_ended
FROM
  datalake_ebdb_clean.listing_business_context AS bl
INNER JOIN
  datalake_sale_listings.sale_listing_price_changes AS p_sale
    ON p_sale.id_house = bl.id_house
      AND bl.business_context = 'SALE'
