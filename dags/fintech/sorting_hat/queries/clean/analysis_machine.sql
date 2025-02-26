SELECT
  id,
  analysis_request_id as id_analysis_request,
  CAST(GET_JSON_OBJECT(context, '$.proposal_id') AS INTEGER) AS id_proposal,
  subject_id as id_subject,
  status,
  subject_type,
  type,
  is_current_machine,
  machine_version,
  context,
  CAST(GET_JSON_OBJECT(context, '$.risk_category') AS STRING) AS risk_category,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.analysismachine
