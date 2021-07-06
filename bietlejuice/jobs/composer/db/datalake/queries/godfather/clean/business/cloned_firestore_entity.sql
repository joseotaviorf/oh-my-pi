SELECT
  id,
  revived_offer_id as id_revived_offer,
  version,
  `type`,
  firestore_source,
  firestore_target,
  created_at as ts_created,
  updated_at as ts_updated
FROM datalake_godfather_raw.business_cloned_firestore_entity
