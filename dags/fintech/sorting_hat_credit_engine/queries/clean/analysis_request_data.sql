SELECT
  id,
  analysis_request_id as id_analysis_request,
  state_machine_id as id_state_machine,
  source_id as id_source,
  attributes,
  raw_data,
  source_entity,
  version,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.analysisrequestdata

