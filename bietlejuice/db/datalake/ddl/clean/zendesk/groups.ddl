DROP TABLE datalake_clean.zendesk_groups;

CREATE EXTERNAL TABLE datalake_clean.`zendesk_groups`(
  `url` string,
  `id` string,
  `name` string,
  `deleted` string,
  `created_at` string,
  `updated_at` string)
PARTITIONED BY (
  `dt_extraction` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/zendesk/groups/'

MSCK REPAIR TABLE datalake_clean.zendesk_groups;