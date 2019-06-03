DROP TABLE datalake_raw.zendesk_group_memberships;

CREATE EXTERNAL TABLE datalake_raw.`zendesk_group_memberships`(
  `url` string,
  `id` string,
  `user_id` string,
  `group_id` string,
  `default` string,
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
  's3://5a-datalake/raw/zendesk/group_memberships/'

MSCK REPAIR TABLE datalake_raw.zendesk_group_memberships;