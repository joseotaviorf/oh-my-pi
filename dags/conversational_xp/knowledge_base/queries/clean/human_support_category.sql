SELECT
  id,
  content_id AS id_content,
  title,
  status,
  updated_at AS ts_updated,
  created_at AS ts_created
FROM
  datalake_knowledge_base_raw.human_support_category
