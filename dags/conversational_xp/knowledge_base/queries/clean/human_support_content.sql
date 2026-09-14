SELECT
  id,
  content_id AS id_content,
  quick_questions_id AS id_quick_questions,
  title,
  country,
  customer_type,
  taxonomy,
  link_to_training,
  status,
  support_analyst_faq,
  type AS content_type,
  resume,
  slug,
  needs_update_tsv_body,
  updated_at AS ts_updated,
  created_at AS ts_created
FROM
  datalake_knowledge_base_raw.human_support_content
