DROP TABLE IF EXISTS datalake_raw.marketing_lifull_campaigns;

CREATE EXTERNAL TABLE datalake_raw.marketing_lifull_campaigns(
  `id`           string,
  `name`         string,
  `account_name` string,
  `clicks`       string,
  `conversions`  string,
  `desktop_cost` string,
  `mobile_cost`  string,
  `total_cost`   string,
  `curr_date`    string,
  `group_name`   string)
PARTITIONED BY(
  acc string,
  dt  string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json' = 'true'
)
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/lifull_campaigns/';

MSCK REPAIR TABLE datalake_raw.marketing_lifull_campaigns;