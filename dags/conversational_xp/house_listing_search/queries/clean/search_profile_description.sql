SELECT
  id,
  search_profile_id AS id_search_profile,
  description AS profile_description,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_house_listing_search_raw.search_profile_description
