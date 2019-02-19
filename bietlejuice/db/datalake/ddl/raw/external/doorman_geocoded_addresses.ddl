create external table datalake_raw.doorman_geocoded_addresses (
  id_user_doorman string,
  geocode_hash string,
  google_formatted_address string,
  lat string,
  lng string,
  location_type string,
  place_id string,
  types string
)
stored as parquet
location 's3://5a-datalake/raw/external/doorman_geocoded_addresses/'
;
