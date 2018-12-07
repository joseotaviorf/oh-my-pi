DROP TABLE datalake_raw.marketing_google_campaigns;

CREATE EXTERNAL TABLE datalake_raw.marketing_google_campaigns (
  customer_id string,
  campaign_id string,
  campaign_name string,
  clicks string,
  click_type string,
  cost string,
  date string,
  device string,
  impressions string,
  account_name string,
  hour_of_day string,
  month string,
  labels string,
  week string,
  year string)
PARTITIONED BY (
  acc string,
  dt string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/google_ads/campaigns_performance_report/'

MSCK REPAIR TABLE datalake_raw.marketing_google_campaigns;