DROP TABLE datalake_raw.marketing_google_ads_keywords;

CREATE EXTERNAL TABLE datalake_raw.marketing_google_ads_keywords (
  customerid string,
  adgroupid string,
  adgroupname string,
  campaignid string,
  campaignname string,
  clicks string,
  clicktype string,
  cost string,
  date string,
  device string,
  id string,
  impressions string,
  keywordmatchtype string,
  labels string,
  criteria string,
  accountdescriptivename string)
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
  's3://5a-datalake/raw/marketing/google_ads/keywords_performance_report/'

MSCK REPAIR TABLE datalake_raw.marketing_google_ads_keywords;