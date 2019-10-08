DROP TABLE IF EXISTS datalake_clean.house_listing;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.house_listing (
  sk_house_listing string,
  id_house string,
  version string,
  status string,
  ts_listing_version_start string,
  ts_listing_version_end string,
  listing_category_start string,
  is_exclusive string,
  dt_last_exclusive_opted_in string,
  dt_last_exclusive_opted_out string,
  is_originals_active string,
  last_originals_type string,
  dt_last_originals_opted_in string,
  dt_last_originals_opted_out string,
  is_iorent_active string,
  last_iorent_type string,
  dt_last_iorent_opted_in string,
  dt_last_iorent_opted_out string,
  ts_load string
 )
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/house/house_listing/'
tblproperties (
  'skip.header.line.count' = '1'
);