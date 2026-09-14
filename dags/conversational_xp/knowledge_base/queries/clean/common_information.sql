SELECT
  id,
  content_id AS id_content,
  type AS information_type,
  title,
  content,
  status,
  updated_at AS ts_updated,
  created_at AS ts_created
FROM
  datalake_knowledge_base_raw.common_information
