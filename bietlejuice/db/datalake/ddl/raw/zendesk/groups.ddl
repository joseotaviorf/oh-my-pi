DROP TABLE datalake_raw.zendesk_groups;

CREATE EXTERNAL TABLE datalake_raw.`zendesk_groups`(
  `url` string,
  `id` string,
  `name` string,
  `deleted` string,
  `created_at` string,
  `updated_at` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/zendesk/groups/'

MSCK REPAIR TABLE datalake_raw.zendesk_groups;