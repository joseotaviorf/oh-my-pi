SELECT
  id_house_status AS sk_house_status,
  house_status,
  status_reason,
  NOW() AS ts_load
FROM
  datalake_ebdb_listing.house_status
