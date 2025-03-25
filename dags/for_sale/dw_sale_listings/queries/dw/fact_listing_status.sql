SELECT
  sls.id_sale_listing AS sk_sale_listing,
  COALESCE(sls.id_user_revision, -1) AS sk_user_revision,
  COALESCE(sls.id_region, -1) AS sk_region,
  COALESCE(cs_supply.sk_company, -1) AS sk_company,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_first_publication, 'yyyyMMdd')), -1) AS sk_first_publication_date,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_status_started, 'yyyyMMdd')), -1) AS sk_status_start_date,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_status_ended, 'yyyyMMdd')), -1) AS sk_status_end_date,
  sls.status_history,
  sls.status_closing_history,
  sls.status_change_reason,
  LEFT(sls.status_change_reason_detail, 5000) AS status_change_reason_detail,
  sls.is_last_status,
  sls.ts_status_started,
  sls.ts_status_ended,
  NOW() AS ts_load
FROM 
  datalake_sale_listings.sale_listing_status AS sls
LEFT JOIN
  datalake_company.company_sks AS cs_supply
    ON (
      sls.uuid_company IS NOT NULL
      AND sls.uuid_company = cs_supply.uuid_company
    ) OR (
      sls.uuid_company IS NULL
      AND sls.id_company_hubspot IS NOT NULL
      AND sls.id_company_hubspot = cs_supply.id_hubspot
    )