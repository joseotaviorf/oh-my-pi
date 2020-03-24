DROP TABLE IF EXISTS datalake_raw.marketing_manual_shared_costs;

CREATE EXTERNAL TABLE datalake_raw.marketing_manual_shared_costs (
  account_name string, 
  ad_group_name string, 
  campaign_name string, 
  city_group string,
  cost string,
  cost_share_desktop string,
  cost_share_mobile string,
  cost_share_other string,
  dt string,
  mkt_business string, 
  mkt_channel string, 
  mkt_medium string, 
  mkt_origin string, 
  mkt_source string, 
  side string,
  utm_content string, 
  utm_term string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location
    's3://5a-datalake/raw/gsheets/marketing/cost_sharing/manual_shared_costs/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
