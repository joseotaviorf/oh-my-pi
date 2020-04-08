DROP TABLE IF EXISTS datalake_raw.marketing_name_convention_shared_costs;

CREATE EXTERNAL TABLE datalake_raw.marketing_name_convention_shared_costs (
  account_name string,
  cost string,
  dt string,
  mkt_business string,
  mkt_channel string,
  mkt_medium string,
  mkt_origin string,
  mkt_source string,
  rule_id string,
  side string
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
