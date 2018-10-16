drop table if exists datalake_clean.ods_dim_region;
create external table if not exists datalake_clean.ods_dim_region (
  sk_region string,
  id string,
  level string,
  name string,
  macro_id string,
  macro_name string,
  city_id string,
  city_name string,
  region_code string,
  new_region_code string,
  short_region_name string,
  long_region_name string,
  greater_region string,
  dt_created string,
  dt_updated string,
  dt_timestamp string,
  dt_first_property_created string,
  dt_first_booking string,
  days_from_first_booking string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/region'
tblproperties (
  'skip.header.line.count' = '1'
)
;