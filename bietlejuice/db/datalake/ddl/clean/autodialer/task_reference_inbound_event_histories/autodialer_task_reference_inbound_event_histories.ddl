DROP TABLE datalake_clean.autodialer_task_reference_inbound_event_histories;

CREATE EXTERNAL TABLE datalake_clean.`autodialer_task_reference_inbound_event_histories`(
  `level_0` bigint,
  `_class` string,
  `active` boolean,
  `address` string,
  `agent_id` bigint,
  `assignee` string,
  `call_type` string,
  `callanalyzer` string,
  `class` string,
  `created_at` string,
  `dial_status` string,
  `email` string,
  `event_date` bigint,
  `hangupcause` string,
  `id` string,
  `index` bigint,
  `name` string,
  `phones` string,
  `score` double,
  `sipcause` string,
  `snoozed` double,
  `task_id` string,
  `task_link` string,
  `task_reference_event_origin` string,
  `task_type` string,
  `updated_at` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/autodialer/task_reference_inbound_event_histories/task_reference_inbound_event_histories/'

msck repair table datalake_clean.autodialer_task_reference_inbound_event_histories