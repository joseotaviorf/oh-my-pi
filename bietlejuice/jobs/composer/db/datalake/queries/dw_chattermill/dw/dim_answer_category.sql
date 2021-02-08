SELECT
  DISTINCT
  CAST(COALESCE(id_tag_theme, -1) AS INTEGER) AS sk_category,
  tag_parent AS category,
  tag_name AS theme,
  current_timestamp AS ts_load
FROM
  datalake_chattermill.responses
