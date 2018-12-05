DROP TABLE datalake_raw.marketing_google_ads;

CREATE EXTERNAL TABLE datalake_raw.marketing_google_ads (
  customerid string,
  adgroupid string,
  adgroupname string,
  adtype string,
  campaignid string,
  campaignname string,
  clicks string,
  clicktype string,
  cost string,
  criterionid string,
  date string,
  device string,
  id string,
  impressions string,
  labels string,
  imagecreativename string,
  accountdescriptivename string,
  description string,
  description1 string,
  description2 string)
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
  's3://5a-datalake/raw/marketing/google_ads/ads_performance_report/'

MSCK REPAIR TABLE datalake_raw.marketing_google_ads;