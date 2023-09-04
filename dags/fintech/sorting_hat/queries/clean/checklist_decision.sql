SELECT
  id,
  checklist_id AS id_checklist,
  input_source_id AS id_input_source,
  type,
  input_source_type,
  decision,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_sorting_hat_raw.checklistdecision