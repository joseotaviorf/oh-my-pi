drop table if exists datalake_clean.external_property;
create external table datalake_clean.external_property (
  id bigint,
  website string,
  url string,
  http_status smallint,
  crawled_on string,
  updated_on string,
  business string,
  type string,
  advertiser_name string,
  advertiser_type string,
  primary_phone_number string,
  secondary_phone_number string,
  price double,
  rent double,
  condominium double,
  iptu double,
  total_area double,
  useful_area double,
  bedrooms double,
  suites double,
  toilets double,
  garages double,
  photos string,
  description string,
  year_building double,
  unit_features string,
  common_features string,
  complementary_info string,
  cep string,
  lat double,
  lng double,
  street string,
  neighborhood string,
  city string,
  state string,
  craw_timestamp double
)
partitioned by (
  started_on date
)
stored as parquet
location 's3://5a-datalake/clean/external_property/'
;

msck repair table datalake_clean.external_property;
