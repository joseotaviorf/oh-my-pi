DROP TABLE IF EXISTS datalake_raw.marketing_manual_shared_costs;

CREATE EXTERNAL TABLE datalake_raw.marketing_manual_shared_costs (
  dt string,
  side string,
  city_group string,
  account_name string,
  campaign_name string,
  ad_group_name string,
  utm_term string,
  utm_content string,
  mkt_business string,
  mkt_origin string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string,
  cost string,
  cost_share_mobile string,
  cost_share_desktop string,
  cost_share_other string
)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
location
    's3://5a-datalake/raw/gsheets/marketing/cost_sharing/manual_shared_costs/'
;
