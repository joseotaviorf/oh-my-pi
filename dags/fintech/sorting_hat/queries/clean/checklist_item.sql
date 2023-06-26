SELECT
  id,
  checklist_group_id as id_checklist_group,
  input_source_id as id_input_source,
  input_description,
  input_source_name,
  input_source_type,
  input_type,
  input_value,
  type,
  status,
  is_compliant,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.checklistitem