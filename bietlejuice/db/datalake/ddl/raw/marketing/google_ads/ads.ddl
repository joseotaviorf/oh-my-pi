CREATE EXTERNAL TABLE datalake_raw.marketing_google_ads_ads (
  customerid varchar,
  adgroupid varchar,
  adgroupname varchar,
  adtype varchar,
  campaignid varchar,
  campaignname varchar,
  clicks varchar,
  clicktype varchar,
  cost varchar,
  keywordid varchar,
  date varchar,
  device varchar,
  id varchar,
  impressions varchar,
  labels varchar,
  imagecreativename varchar,
  accountdescriptivename varchar,
  description varchar,
  description1 varchar,
  description2 varchar)
PARTITIONED BY (
  acc varchar,
  dt varchar)
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