drop table if exists datalake_clean.ods_fact_house_listing_status;
create external table if not exists datalake_clean.ods_fact_house_listing_status (
  sk_house_listing string,
  sk_region string,
  sk_first_publication_date string,
  sk_status_start_date string,
  sk_status_end_date string,
  ts_status_start string,
  ts_status_end string,
  status_history string,
  status_change_reason string,
  is_last_status_of_day string,
  ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/house_listing_status'
tblproperties (
  'skip.header.line.count' = '1'
);
