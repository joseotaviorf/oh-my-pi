SELECT
  id,
  offer_id as id_offer,
  firestore_id as id_firestore,
  offer_firestore_id as id_offer_firestore,
  version,
  `status`,
  `type`,
  raw_document,
  created_at as ts_created,
  updated_at as ts_updated
FROM
  datalake_godfather_raw.topic
