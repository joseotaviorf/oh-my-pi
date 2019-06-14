SELECT *
FROM datalake_clean.ods_dim_house_listing
WHERE
  COALESCE(house_lng, '') NOT IN ('', '0')
  AND COALESCE(house_lat, '') NOT IN ('', '0')
