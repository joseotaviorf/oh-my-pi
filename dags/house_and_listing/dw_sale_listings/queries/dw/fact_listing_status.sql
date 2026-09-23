SELECT
  sls.id_sale_listing AS sk_sale_listing,
  COALESCE(sls.id_user_revision, -1) AS sk_user_revision,
  COALESCE(sls.id_region, -1) AS sk_region,
  COALESCE(cb.sk_broker, '-1') AS sk_broker,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_first_publication, 'yyyyMMdd')), -1) AS sk_first_publication_date,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_status_started, 'yyyyMMdd')), -1) AS sk_status_start_date,
  COALESCE(BIGINT(DATE_FORMAT(sls.ts_status_ended, 'yyyyMMdd')), -1) AS sk_status_end_date,
  sls.status_history,
  sls.status_closing_history,
  sls.status_change_reason,
  LEFT(sls.status_change_reason_detail, 5000) AS status_change_reason_detail,
  sls.deactivation_reason,
  sls.deactivation_reason_category,
  sls.deactivation_additional_context,
  sls.is_last_status,
  sls.ts_status_started,
  sls.ts_status_ended,
  NOW() AS ts_load
FROM 
  datalake_sale_listings.sale_listing_status AS sls
LEFT JOIN
  core_brokers.brokers AS cb
    ON sls.uuid_company = cb.uuid_company