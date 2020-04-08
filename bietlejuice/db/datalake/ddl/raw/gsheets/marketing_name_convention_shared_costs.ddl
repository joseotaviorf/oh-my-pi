DROP TABLE IF EXISTS datalake_raw.marketing_name_convention_shared_costs;

CREATE EXTERNAL TABLE datalake_raw.marketing_name_convention_shared_costs (
  dt string,
  side string,
  account_name string,
  rule_id string,
  mkt_business string,
  mkt_origin string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string,
  cost string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location
    's3://5a-datalake/raw/gsheets/marketing/cost_sharing/name_convention_shared_costs/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
