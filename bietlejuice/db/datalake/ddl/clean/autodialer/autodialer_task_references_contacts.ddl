DROP TABLE datalake_clean.autodialer_task_references_contacts;

CREATE EXTERNAL TABLE datalake_clean.`autodialer_task_references_contacts`(
  `id` string,
  `address` string,
  `email` string,
  `name` string,
  `phones` string)
PARTITIONED BY (
  `dt_extraction` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/autodialer/task_references_contacts/'

msck repair table datalake_clean.autodialer_task_references_contacts