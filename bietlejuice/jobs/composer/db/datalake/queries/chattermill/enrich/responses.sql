WITH responses_explode AS (
  SELECT
      id,
      GET_JSON_OBJECT(GET_JSON_OBJECT(user_attributes,'$.response_id'),'$.value') AS id_response,
      GET_JSON_OBJECT(GET_JSON_OBJECT(user_attributes,'$.name'),'$.value') AS name,
      GET_JSON_OBJECT(GET_JSON_OBJECT(user_attributes,'$.email'),'$.value') AS email,
      GET_JSON_OBJECT(GET_JSON_OBJECT(user_attributes,'$.telephone'),'$.value') AS telephone,
      GET_JSON_OBJECT(GET_JSON_OBJECT(user_attributes,'$.collected_by'),'$.value') AS collected_by,
      GET_JSON_OBJECT(GET_JSON_OBJECT(user_attributes,'$.previous_score'),'$.value') AS previous_score,
      score,
      comment,
      original_comment,
      data_type,
      data_source,
      dataset,
      EXPLODE(themes) AS exploded_themes,
      created_at AS ts_created,
      updated_at AS ts_updated
  FROM
      datalake_chattermill_clean.responses
)
SELECT
  id,
  id_response,
  exploded_themes["id"] AS id_tag_theme,
  exploded_themes["parent_id"] AS id_tag_parent,
  name,
  email,
  telephone,
  collected_by,
  previous_score,
  score,
  comment,
  original_comment,
  data_type,
  data_source,
  dataset,
  exploded_themes["parent"] AS tag_parent,
  exploded_themes["name"] AS tag_name,
  exploded_themes["sentiment"] AS tag_sentiment,
  ts_created,
  ts_updated
FROM
  responses_explode
