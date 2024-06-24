SELECT
  sl.id_sale_listing AS sk_sale_listing,
  lbc.id_house AS sk_house,
  h.id_company_hubspot AS sk_company_hubspot,
  hslc.consultant_type,
  hslc.first_consultant_type,
  lbc.status AS status,
  NULLIF(h.sale_price, 0) AS price,
  hpp.p_30 AS predicted_price_30,
  hpp.p_70 AS predicted_price_70,
  hpp.p_50 AS predicted_price,
  hpp.certainty AS predicted_price_certainty,
  lbc.status_closing AS closing_status,
  COALESCE(ssl.stranded_status, 'NA') AS stranded_status,
  hrs.registration_abandoned_reason,
  lbc.status_reason AS unpublished_reason,
  lbc.short_url,
  ll.price_bin,
  ll.price_m2_bin,
  ll.total_area_bin,
  ll.pricing_full_name AS pricing_lens_tier,
  ll.demand_full_name AS demand_lens_tier,
  ll.availability_full_name AS availability_lens_tier,
  ll.sellability_full_name AS sellability_lens_tier,
  ll.listing_quality_full_name AS listing_quality_lens_tier,
  ll.pricing_disclaimer AS pricing_lens_disclaimer,
  ll.demand_disclaimer AS demand_lens_disclaimer,
  ll.availability_disclaimer AS availability_lens_disclaimer,
  ll.availability_drill_down AS availability_lens_drill_down,
  ll.listing_quality_disclaimer AS listing_quality_lens_disclaimer,
  ll.listing_quality_drill_down AS listing_quality_lens_drill_down,
  CASE
    WHEN h.is_sale_3p_supply THEN h.partner_3p_supply
  END AS partner_3p_supply,
  h.is_sale_3p_supply AS is_3p_supply,
  h.is_3p_supply_5a AND h.is_sale_3p_supply AS is_3p_supply_5a,
  h.is_3p_supply_bh AND h.is_sale_3p_supply AS is_3p_supply_bh,
  h.is_casa_mineira_migration,
  h.is_sale_primary_market AS is_primary_market,
  ssl.is_offer_and_visit_stranded,
  sl.is_for_rent,
  sl.has_active_rental_contract,
  sl.has_house_been_rented,
  h.has_sale_great_price_tag AS has_great_price_tag,
  h.has_sale_smart_price_activated AS has_smart_price_activated,
  pc.is_smart_price_change AS has_price_by_smart_price_feature,
  hslc.dt_consultant_started,
  hslc.ts_consultant_deleted,
  lbc.ts_created,
  lbc.ts_first_listing AS ts_first_publication,
  lbc.ts_last_listing AS ts_last_publication,
  sl.ts_first_depublication,
  sl.ts_last_depublication,
  sld.ts_first_booking,
  sld.ts_first_visit_completed,
  sld.ts_first_offer_submitted,
  sld.dt_first_offer_accepted,
  sld.dt_first_sale_agreement_signed,
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
JOIN
  datalake_sale_listing_demand.sale_listing_demand AS sld
    ON lbc.id_house = sld.id_house
LEFT JOIN
  datalake_sale_listings.sale_listing_price_changes AS pc
    ON lbc.id_house = pc.id_house
    AND pc.is_last_price IS TRUE
LEFT JOIN
  datalake_ebdb_clean.house_registration_status AS hrs
    ON hrs.id_house = lbc.id_house
LEFT JOIN
  datalake_big_agent.house_sale_listing_consultant AS hslc
    ON hslc.id_sale_listing = sl.id_sale_listing
    AND hslc.is_last_ciq_on_listing = True
LEFT JOIN
    datalake_ebdb_clean.house_predicted_price AS hpp
      ON hpp.id_house = lbc.id_house
      AND hpp.business_context = 'SALE'
LEFT JOIN
  datalake_sale_stranded_listings.stranded_status AS ssl
    ON ssl.id_sale_listing = sl.id_sale_listing
    AND ssl.is_last_status = True
LEFT JOIN
  datalake_sale_listings_lenses.listing_lenses AS ll
    ON ll.id_house = lbc.id_house
WHERE
  lbc.business_context = 'SALE'
