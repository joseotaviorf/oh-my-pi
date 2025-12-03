SELECT
  id,
  portal_id AS id_portal,
  publisher_id AS id_publisher,
  listing_status,
  created_at AS ts_created
FROM
  datalake_vespucio_service_raw.publisher
