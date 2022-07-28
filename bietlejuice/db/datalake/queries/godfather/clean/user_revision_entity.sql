SELECT
  id,
  author_id AS id_author,
  `timestamp` AS ts_revision
FROM
  datalake_godfather_raw.user_revision_entity
