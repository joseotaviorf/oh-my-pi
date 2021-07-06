SELECT
  id,
  firestore_id as id_firestore,
  topic_id as id_topic,
  author_id as id_author,
  version,
  `type`,
  iteration,
  `text`,
  turn,
  raw_document,
  created_at as ts_created,
  updated_at as ts_updated
FROM datalake_godfather_raw.message
