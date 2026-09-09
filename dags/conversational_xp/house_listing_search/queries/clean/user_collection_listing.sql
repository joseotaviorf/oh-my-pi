SELECT
  id,
  user_collection_id AS id_user_collection,
  listing_id AS id_listing,
  business_context,
  listing_origin,
  updated_at AS ts_updated
FROM
  datalake_house_listing_search_raw.user_collection_listing
