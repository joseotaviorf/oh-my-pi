SELECT
  id,
  client_selfie_document_id as id_client_selfie_document,
  rev,
  revtype as rev_type,
  `type`,
  type_mod as mod_type,
  client_selfie_document_mod as mod_client_selfie_document,
  path_front_mod as mod_path_front,
  path_back,
  path_back_mod as mod_path_back,
  path_front
FROM
  datalake_godfather_raw.client_document_aud
