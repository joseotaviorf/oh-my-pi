SELECT
  parent_id AS id_parent,
  child_id AS id_child,
  child_order
FROM
  datalake_knowledge_base_raw.human_support_category_children
