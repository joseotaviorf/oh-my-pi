SELECT
  id,
  `status`,
  rejection_reason,
  created_at as ts_created
FROM datalake_godfather_raw.business_offer_manual_rejection
