SELECT
  CAST(COALESCE(id_response_tag, -1) AS BIGINT) AS sk_answer_category,
  CAST(COALESCE(id, -1) AS BIGINT) AS sk_answer_classification,
  CAST(COALESCE(id_response, -1) AS INTEGER) AS sk_answer,
  CAST(COALESCE(id_tag_theme, -1) AS INTEGER) AS sk_category,
  COALESCE(CAST(DATE_FORMAT(ts_created, 'yyyyMMdd') AS INTEGER), -1) AS sk_answer_classification_created_date,
  COALESCE(CAST(DATE_FORMAT(ts_updated, 'yyyyMMdd') AS INTEGER), -1) AS sk_answer_classification_updated_date,
  CAST(tag_sentiment AS SMALLINT) AS sentiment,
  CAST(score AS SMALLINT) AS score,
  original_comment,
  comment,
  current_timestamp AS ts_load
FROM
  datalake_chattermill.responses
