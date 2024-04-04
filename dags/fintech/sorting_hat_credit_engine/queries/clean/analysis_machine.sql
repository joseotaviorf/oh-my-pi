SELECT
  id,
  analysis_request_id as id_analysis_request,
  subject_id as id_subject,
  status,
  subject_type,
  type,
  is_current_machine,
  machine_version,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.analysismachine