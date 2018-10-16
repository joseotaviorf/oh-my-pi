CREATE EXTERNAL TABLE datalake_raw.marketing_googleads_keywords(
  customerid varchar,
  adgroupid varchar,
  adgroupname varchar,
  campaignid varchar,
  campaignname varchar,
  clicks varchar,
  clicktype varchar,
  cost varchar,
  date varchar,
  device varchar,
  id varchar,
  impressions varchar,
  keywordmatchtype varchar,
  labels varchar,
  criteria varchar,
  accountdescriptivename varchar)
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
  's3://5a-datalake/raw/marketing/google_ads/keywords_performance_report/'