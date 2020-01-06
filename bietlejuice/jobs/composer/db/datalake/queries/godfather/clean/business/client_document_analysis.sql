SELECT
  id,
  client_document_id as id_client_document,
  client_selfie_document_analysis_id as id_client_selfie_document_analysis,
  version,
  front_labels,
  back_labels,
  updated_at as ts_updated,
  created_at as ts_created
FROM datalake_godfather_raw.business_client_document_analysis
