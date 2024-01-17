SELECT DISTINCT
  CRC32(CONCAT(status, IFNULL(status_reason, ''))) AS id_house_status,
  status AS house_status,
  status_reason
FROM
  datalake_ebdb_listing.house_listing
WHERE
  status IS NOT NULL
  OR status_reason IS NOT NULL