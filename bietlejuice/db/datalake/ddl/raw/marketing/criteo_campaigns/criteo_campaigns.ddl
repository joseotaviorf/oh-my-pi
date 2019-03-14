DROP TABLE datalake_raw.marketing_criteo_campaigns;

CREATE EXTERNAL TABLE datalake_raw.marketing_criteo_campaigns (
  `Advertiser Name` string,
  `Campaign ID` string,
  `Campaign Name` string,
  `Day` string,
  `Currency` string,
  `Clicks` string,
  `Impressions` string,
  `Audience` string,
  `Cost` string,
  `All Sales` string,
  `Revenue` string,
  `Comp. Win` string,
  `CPC` string)
PARTITIONED BY (
  acc string,
  dt string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json'   = 'true'
)
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/criteo_campaigns/'

MSCK REPAIR TABLE datalake_raw.marketing_criteo_campaigns;