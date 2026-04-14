SELECT
  id,
  search_profile_id AS id_search_profile,
  filters AS filters_json,
  events_count,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_house_listing_search_raw.search_profile_filters
