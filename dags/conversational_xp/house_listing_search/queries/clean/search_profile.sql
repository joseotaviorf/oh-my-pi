SELECT
  id,
  external_id AS uuid_external_id,
  profile_holder_id AS id_profile_holder,
  profile_holder_type,
  business_context,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_house_listing_search_raw.search_profile
