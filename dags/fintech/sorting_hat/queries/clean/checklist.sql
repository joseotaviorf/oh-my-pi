SELECT
  id,
  analysis_request_id as id_analysis_request,
  result,
  status,
  type,
  is_current_checklist,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.checklist