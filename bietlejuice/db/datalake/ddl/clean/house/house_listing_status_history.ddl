DROP TABLE IF EXISTS datalake_clean.house_listing_status_history;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.house_listing_status_history (
  sk_house_listing string,
  id_house string,
  rev string,
  status_mod string,
  status_history string,
  ts_first_publication string,
  ts_status_start string,
  ts_status_end string,
  status_order string,
  reason string
 )
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/house/house_listing_status_history/'
tblproperties (
  'skip.header.line.count' = '1'
);