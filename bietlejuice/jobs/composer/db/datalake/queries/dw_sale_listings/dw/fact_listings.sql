SELECT
  sl.id_sale_listing AS sk_sale_listing,
  sl.id_house AS sk_house,
  h.id_user AS sk_owner,
  h.id_region AS sk_region,
  COALESCE(BIGINT(DATE_FORMAT(sl.ts_first_publication, 'yyyyMMdd')), -1) AS sk_first_publication_date,
  COALESCE(BIGINT(DATE_FORMAT(sl.ts_last_publication, 'yyyyMMdd')), -1) AS sk_last_publication_date,
  COALESCE(BIGINT(DATE_FORMAT(sl.ts_first_depublication, 'yyyyMMdd')), -1) AS sk_first_depublication_date,
  COALESCE(BIGINT(DATE_FORMAT(sl.ts_last_depublication, 'yyyyMMdd')), -1) AS sk_last_depublication_date,
  sl.days_last_publication_to_depublication,
  sl.days_first_publication_to_first_depublication,
  sl.days_first_publication_to_last_depublication,
  sl.days_first_publication_to_first_sale_flow,
  sl.days_first_publication_to_first_booking,
  sl.days_first_publication_to_first_sale_agreement_signed,
  sl.days_first_publication_to_house_registry_ended,
  sl.unpublications AS total_depublications,
  sl.days_as_published,
  NOW() AS ts_load
FROM
  datalake_sale_listings.sale_listing AS sl
JOIN 
  datalake_ebdb_clean.house AS h
    ON sl.id_house = h.id