DROP TABLE datalake_clean.zendesk_group_memberships_xplenty;

CREATE EXTERNAL TABLE datalake_clean.`zendesk_group_memberships_xplenty`(
  `url` string,
  `id` string,
  `user_id` string,
  `group_id` string,
  `default` string,
  `created_at` string,
  `updated_at` string)
PARTITIONED BY (
  `dt_extraction` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/zendesk/group_memberships_xplenty/'

MSCK REPAIR TABLE datalake_clean.zendesk_group_memberships_xplenty;