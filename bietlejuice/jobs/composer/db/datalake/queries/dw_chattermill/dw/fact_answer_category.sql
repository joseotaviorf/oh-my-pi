SELECT
  COALESCE(id_response_tag, -1) AS sk_answer_category,
  COALESCE(id, -1) AS sk_answer_classification,
  COALESCE(id_response, -1) AS sk_answer,
  COALESCE(id_tag_theme, -1) AS sk_category,
  COALESCE(CAST(date_format(ts_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_answer_classification_created_date,
  COALESCE(CAST(date_format(ts_updated, 'yyyyMMdd') AS BIGINT), -1) AS sk_answer_classification_updated_date,
  tag_sentiment AS sentiment,
  score,
  original_comment,
  comment,
  current_timestamp AS ts_load
FROM
  datalake_chattermill.responses
