SELECT
  sls.id_sale_listing AS sk_sale_listing,
  COALESCE(sls.id_region, -1) AS sk_region,
  COALESCE(cs_supply.sk_company, -1) AS sk_company,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_first_publication, 'yyyyMMdd')), -1) AS sk_first_publication_date,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_status_started, 'yyyyMMdd')), -1) AS sk_status_start_date,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_status_ended, 'yyyyMMdd')), -1) AS sk_status_end_date,
  sls.ts_status_started,
  sls.ts_status_ended,
  sls.status_history,
  LEFT(sls.status_change_reason, 5000) AS status_change_reason,
  sls.is_last_status,
  NOW() AS ts_load
FROM 
  datalake_sale_listings.sale_listing_status AS sls
LEFT JOIN
  datalake_rede_company.company_sks AS cs_supply
    ON (sls.id_company_hubspot IS NOT NULL
    AND sls.id_company_hubspot = cs_supply.id_hubspot)
    OR (sls.id_company_hubspot IS NULL
    AND sls.partner_3p_supply = cs_supply.extracted_3p_tag)
