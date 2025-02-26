SELECT
  id,
  analysis_request_id as id_analysis_request,
  state_machine_id as id_state_machine,
  attributes,
  document_type,
  document_number,
  raw_data,
  source_entity,
  source_id as id_source,
  version,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.analysisrequestproponentdata

