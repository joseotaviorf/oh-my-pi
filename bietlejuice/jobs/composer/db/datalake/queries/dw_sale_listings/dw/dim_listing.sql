SELECT
  sl.id_sale_listing AS sk_sale_listing,
  lbc.id_house AS sk_house,
  NULLIF(h.sale_price, 0) AS price,
  lbc.calculator_price AS predicted_price,
  lbc.status AS status,
  lbc.status_closing AS closing_status,
  hrs.registration_abandoned_reason,
  lbc.status_reason AS unpublished_reason,
  lbc.short_url,
  lbc.is_rent_context AS is_for_rent,
  lbc.ts_created,
  lbc.ts_first_listing AS ts_first_publication,
  lbc.ts_last_listing AS ts_last_publication,
  sl.ts_first_depublication,
  sl.ts_last_depublication,
  lbc.ts_updated,
  NOW() AS ts_load
FROM
  datalake_ebdb_listing.listing_business_context AS lbc
JOIN
  datalake_ebdb_clean.house AS h
    ON h.id = lbc.id_house
JOIN
  datalake_sale_listings.sale_listing AS sl
    ON lbc.id_house = sl.id_house
LEFT JOIN
  datalake_ebdb_clean.house_registration_status AS hrs
    ON hrs.id_house = lbc.id_house
WHERE 
  lbc.business_context = 'SALE'
