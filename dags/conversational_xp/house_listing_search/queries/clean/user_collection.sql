SELECT
  id,
  external_id AS uuid_external_id,
  user_id AS id_user,
  list_type,
  custom_name AS name_custom,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_house_listing_search_raw.user_collection
