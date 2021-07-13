SELECT
  id,
  firestore_id as id_firestore,
  topic_id as id_topic,
  author_id as id_author,
  `type`,
  rev,
  revtype as rev_type,
  iteration,
  text,
  turn,
  firestore_id_mod as mod_id_firestore
FROM
  datalake_godfather_raw.message_aud
