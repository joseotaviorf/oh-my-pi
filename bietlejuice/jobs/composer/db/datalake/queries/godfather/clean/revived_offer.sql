SELECT
  id,
  source_offer_id as id_source_offer,
  target_offer_id as id_target_offer,
  version,
  `status`,
  created_at as ts_created,
  updated_at as ts_updated
FROM datalake_godfather_raw.revived_offer
