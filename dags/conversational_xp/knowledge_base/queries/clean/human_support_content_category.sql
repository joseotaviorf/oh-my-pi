SELECT
  human_support_content_id AS id_human_support_content,
  human_support_category_id AS id_human_support_category,
  category_order
FROM
  datalake_knowledge_base_raw.human_support_content_category
