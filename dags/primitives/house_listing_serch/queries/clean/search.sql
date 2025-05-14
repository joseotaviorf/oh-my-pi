SELECT
  id,
  search_id AS id_search,
  user_id AS id_user,
  search_criteria,
  response,
  created_at AS ts_created
FROM
  datalake_house_listing_search_raw.search