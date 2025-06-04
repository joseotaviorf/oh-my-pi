SELECT
  id,
  user_id AS id_user,
  filter,
  use_case,
  displayed_order,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_house_listing_search_raw.recommendation_user_use_case