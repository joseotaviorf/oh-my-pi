DROP TABLE datalake_clean.task_references;

CREATE EXTERNAL TABLE datalake_clean.`autodialer_task_references_contacts`(
  `id` string,
  `address` string,
  `email` string,
  `name` string,
  `phones` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/autodialer/task_references/task_references_contacts/'

msck repair table datalake_clean.autodialer_task_references_contacts