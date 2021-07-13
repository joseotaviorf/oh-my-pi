SELECT
  id,
  client_id as id_client,
  version,
  type_selected,
  path_selfie,
  created_at as ts_created,
  updated_at as ts_updated
FROM
  datalake_godfather_raw.client_selfie_document
