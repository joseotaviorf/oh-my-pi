SELECT
  id,
  content_id AS id_content,
  title,
  label,
  link,
  description,
  status,
  updated_at AS ts_updated,
  created_at AS ts_created
FROM datalake_knowledge_base_raw.deep_link
