SELECT
  sl.id_sale_listing AS sk_sale_listing,
  sl.id_house AS sk_house,
  h.id_user AS sk_owner,
  h.id_company_hubspot AS sk_company_hubspot,
  CAST(hslc.id_user AS BIGINT) AS sk_user_consultant,
  h.id_region AS sk_region, 
  COALESCE(
    CASE
      WHEN h.is_sale_3p_supply THEN cs_supply.sk_company
    END,
    -1
  ) AS sk_company,
  NULLIF(h.sale_price, 0) AS price,
  h.sale_price/h.total_area AS price_m2,
  COALESCE(BIGINT(DATE_FORMAT(sl.ts_first_publication, 'yyyyMMdd')), -1) AS sk_first_publication_date,
  COALESCE(BIGINT(DATE_FORMAT(sl.ts_last_publication, 'yyyyMMdd')), -1) AS sk_last_publication_date,
  COALESCE(BIGINT(DATE_FORMAT(sl.ts_first_depublication, 'yyyyMMdd')), -1) AS sk_first_depublication_date,
  COALESCE(BIGINT(DATE_FORMAT(sl.ts_last_depublication, 'yyyyMMdd')), -1) AS sk_last_depublication_date,    
  COALESCE(BIGINT(DATE_FORMAT(sld.ts_first_visit_completed, 'yyyyMMdd')), -1) AS sk_first_visit_completed,
  COALESCE(BIGINT(DATE_FORMAT(sld.ts_first_offer_submitted, 'yyyyMMdd')), -1) AS sk_first_offer_submitted_date,
  COALESCE(BIGINT(DATE_FORMAT(sld.dt_first_offer_accepted, 'yyyyMMdd')), -1) AS sk_first_offer_accepted,
  sl.days_last_publication_to_depublication,
  sl.days_first_publication_to_first_depublication,
  sl.days_first_publication_to_last_depublication,
  sld.days_first_publication_to_first_sale_flow,
  sld.days_first_publication_to_first_booking,
  sld.days_first_publication_to_visit_completed,
  sld.days_first_publication_to_first_offer_submitted,
  sld.days_first_publication_to_first_offer_accepted,
  sld.days_first_publication_to_first_sale_agreement_signed,
  sld.days_first_publication_to_house_registry_ended,
  sld.days_first_booking_to_first_visit_completed,
  sld.days_first_visit_completed_to_first_offer_submitted,
  sld.days_first_offer_submitted_to_first_offer_accepted,
  sld.days_first_offer_accepted_to_first_sale_agreement_signed,
  sl.unpublications AS total_depublications,
  sld.total_listings_visit_completed,
  sld.total_listings_offer_submited,
  sld.total_listings_offer_accepted,
  sl.days_as_published,
  NOW() AS ts_load
FROM
  datalake_sale_listings.sale_listing AS sl
JOIN
  datalake_sale_listing_demand.sale_listing_demand AS sld
    ON sl.id_house = sld.id_house
JOIN 
  datalake_ebdb_listing.house AS h
    ON sl.id_house = h.id
LEFT JOIN
  datalake_big_agent.house_sale_listing_consultant AS hslc
    ON sl.id_sale_listing = hslc.id_sale_listing
    AND hslc.is_last_ciq_on_listing = True
LEFT JOIN
  datalake_company.company_sks AS cs_supply
    ON (
      h.uuid_company IS NOT NULL
      AND h.uuid_company = cs_supply.uuid_company
    ) OR (
      h.uuid_company IS NULL
      AND h.id_company_hubspot IS NOT NULL
      AND h.id_company_hubspot = cs_supply.id_hubspot
    ) OR (
       h.uuid_company IS NULL
       AND h.id_company_hubspot IS NULL
       AND h.partner_3p_supply = cs_supply.extracted_3p_tag
    )