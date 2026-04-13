SELECT
  id,
  checklist_id as id_checklist,
  comment_source_id as id_comment_source,
  subject_id as id_subject,
  comment,
  comment_source_name,
  comment_source_type,
  status,
  subject_type,
  is_compliant,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated
FROM
  datalake_sorting_hat_raw.checklistgroup