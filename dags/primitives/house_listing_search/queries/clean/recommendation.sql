SELECT
  id,
  recommendation_id AS id_recommendation,
  user_id AS id_user,
  recommendation_criteria,
  response as final_response,
  original_recommendation_scores AS original_response_scores,
  active_experiments,
  created_at AS ts_created
FROM
  datalake_house_listing_search_raw.recommendation