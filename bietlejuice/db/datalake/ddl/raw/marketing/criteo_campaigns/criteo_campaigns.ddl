DROP TABLE datalake_raw.marketing_criteo_campaigns;

CREATE EXTERNAL TABLE datalake_raw.marketing_criteo_campaigns (
  advertiser_name string,
  campaign_id string,
  campaign_name string,
  day string,
  currency string,
  clicks string,
  impressions string,
  audience string,
  cost string,
  all_sales string,
  revenue string,
  composition_win string,
  cpc string)
PARTITIONED BY (
  dt_extraction string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/criteo_campaigns/criteo_campaigns/'

MSCK REPAIR TABLE datalake_raw.marketing_criteo_campaigns;