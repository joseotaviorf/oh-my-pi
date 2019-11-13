DROP TABLE IF EXISTS datalake_raw.marketing_linkedin_creatives;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_linkedin_creatives(
  id               string,
  campaign         string,
  processing_state string,
  reference        string,
  review           string,
  serving_statuses array<string>,
  status           string,
  type             string,
  variables        string
)
PARTITIONED BY(
  acc string,
  dt  string
)
ROW FORMAT SERDE
'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES ('ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/linkedin_ads/creatives'

MSCK REPAIR TABLE datalake_raw.marketing_linkedin_creatives;