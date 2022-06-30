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
  h.partner_3p_supply,
  h.is_3p_supply,
  sl.is_for_rent,
  sl.has_active_rental_contract,
  sl.has_house_been_rented,
  lbc.ts_created,
  lbc.ts_first_listing AS ts_first_publication,
  lbc.ts_last_listing AS ts_last_publication,
  sl.ts_first_depublication,
  sl.ts_last_depublication,
  sl.ts_first_booking,
  sl.ts_first_visit_completed,
  sl.ts_first_offer_submitted,
  sl.dt_first_offer_accepted,
  sl.dt_first_sale_agreement_signed,
  lbc.ts_updated,
  NOW() AS ts_load
FROM
  datalake_ebdb_listing.listing_business_context AS lbc
JOIN
  datalake_ebdb_listing.house AS h
    ON h.id = lbc.id_house
JOIN
  datalake_sale_listings.sale_listing AS sl
    ON lbc.id_house = sl.id_house
LEFT JOIN
  datalake_ebdb_clean.house_registration_status AS hrs
    ON hrs.id_house = lbc.id_house
WHERE 
  lbc.business_context = 'SALE'