SELECT
  user_id AS id_user,
  article_id AS id_article,
  status,
  updated_at AS ts_updated,
  created_at AS ts_created
FROM
  datalake_knowledge_base_raw.human_support_favorites
