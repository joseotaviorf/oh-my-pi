SELECT
  id,
  client_selfie_document_id as id_client_selfie_document,
  `type`,
  version,
  path_back,
  path_front,
  created_at as ts_created,
  updated_at as ts_updated
FROM datalake_godfather_raw.client_document
