drop table if exists datalake_clean.ods_dim_house_listing;
create external table if not exists datalake_clean.ods_dim_house_listing (
  sk_house_listing string,
  id_house string,
  short_id_house string,
  version string,
  status string,
  ts_listing_version_start string,
  ts_listing_version_end string,
  ts_house_registration_first_verification string,
  ts_house_last_confirmation_availability string,
  ts_house_first_publication string,
  ts_house_last_publication string,
  ts_publication string,
  ts_de_publication string,
  rent string,
  house_rent string,
  house_neighborhood string,
  house_zipcode string,
  house_city string,
  house_complement string,
  house_condo string,
  house_elevator string,
  house_address string,
  house_iptu string,
  house_lat string,
  house_lng string,
  is_house_furnished string,
  house_number string,
  house_bathrooms string,
  house_bedrooms string,
  house_suites string,
  house_garages string,
  house_status string,
  house_type string,
  house_entrance string,
  house_garage_type string,
  is_house_registration_verified string,
  house_total_value string,
  house_total_area string,
  house_construction_area string,
  house_condo_type string,
  house_iptu_type string,
  ts_house_create string,
  ts_house_update string,
  house_unpublished_reason string,
  listing_category_start string,
  listing_category_end string,
  is_last_version string,
  is_exclusive string,
  who_is_living string,
  key_type string,
  key_location string,
  has_visit_restriction string,
  ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/house_listing'
tblproperties (
  'skip.header.line.count' = '1'
)
;