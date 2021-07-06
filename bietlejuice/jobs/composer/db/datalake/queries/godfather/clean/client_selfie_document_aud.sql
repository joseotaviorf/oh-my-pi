SELECT
  id,
  client_id as id_client,
  rev,
  revtype as rev_type,
  client_mod as mod_client,
  type_selected,
  type_selected_mod as mod_type_selected,
  path_selfie,
  path_selfie_mod as mod_path_selfie
FROM datalake_godfather_raw.client_selfie_document_aud
