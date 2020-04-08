DROP TABLE IF EXISTS datalake_raw.affiliates_targets_replanning;
CREATE EXTERNAL TABLE datalake_raw.affiliates_targets_replanning (
  budget string,
  city_group string,
  date string,
  first_listings_target string,
  mkt_origin string,
  mkt_vertical string,
  opportunities_target string,
  prospects_target string,
  qualifieds_target string,
  week_start string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location
    's3://5a-datalake/raw/gsheets/marketing/cost_sharing/auxiliary_sharing_files/affiliates_targets_replanning/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
