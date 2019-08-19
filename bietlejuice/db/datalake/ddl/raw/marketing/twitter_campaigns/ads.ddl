DROP TABLE IF EXISTS datalake_raw.marketing_twitter_ads;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_twitter_ads (
  id string,
  id_line_item string,
  id_account string,
  tweet_id string,
  approval_status string,
  created_at string,
  updated_at string,
  deleted string,
  entity_status string
) PARTITIONED BY (
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
  's3://5a-datalake/raw/marketing/twitter_ads/ads'

MSCK REPAIR TABLE datalake_raw.marketing_twitter_ads;