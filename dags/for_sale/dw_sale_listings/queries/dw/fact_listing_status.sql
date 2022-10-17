SELECT
  sls.id_sale_listing AS sk_sale_listing,
  COALESCE(sls.id_region, -1) AS sk_region,
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