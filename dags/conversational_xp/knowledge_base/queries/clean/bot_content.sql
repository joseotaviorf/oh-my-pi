SELECT
  id,
  content_id AS id_content,
  title,
  country,
  customer_type,
  bot_tags,
  web_content,
  app_content,
  questions,
  status,
  department_front,
  department_back,
  updated_at AS ts_updated,
  created_at AS ts_created
FROM datalake_knowledge_base_raw.bot_content
