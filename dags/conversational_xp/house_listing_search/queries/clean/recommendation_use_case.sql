SELECT
  id,
  listing_id AS id_listing,
  user_use_case_id AS id_user_use_case,
  displayed_order,
  created_at AS ts_created
FROM
  datalake_house_listing_search_raw.recommendation_use_case