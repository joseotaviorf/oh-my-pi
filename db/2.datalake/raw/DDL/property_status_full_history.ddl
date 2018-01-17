drop table if exists datalake_raw.ods_property_status_full_history;
create external table if not exists datalake_raw.ods_property_status_full_history (
  `date` string,
  id string,
  status string,
  status_date string,
  status_time string,
  status_history string,
  current_status string,
  datePublication string,
  published string,
  rnk string,
  first_status_date string,
  last_status_date string,
  next_status_date string,
  next_status_time string,
  next_status string,
  diff_status_time string,
  pub_at_least_min_time_flag string,
  distinct_status_flag string,
  last_position_date_flag string,
  all_status_date_position_flag string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/ods/property_status_full_history/'
;