SELECT
  id,
  state_group_id as id_state_group,
  subject_id as id_subject,
  input,
  raw_input,
  result,
  status,
  subject_type,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.analysisstate
