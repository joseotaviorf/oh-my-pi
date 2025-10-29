SELECT
  id,
  content_id AS id_content,
  theme,
  product,
  journey,
  tags,
  status,
  department_front,
  department_back,
  updated_at AS ts_updated,
  created_at AS ts_created
FROM
  datalake_knowledge_base_raw.meta_information
