SELECT
  id,
  offer_id id_offer,
  offer_firestore_id as id_offer_firestore,
  firestore_id as id_firestore,
  firestore_id_mod as mod_id_firestore,
  rev,
  revtype as rev_type,
  `status`,
  status_mod as mod_status,
  `type`
FROM
  datalake_godfather_raw.topic_aud
