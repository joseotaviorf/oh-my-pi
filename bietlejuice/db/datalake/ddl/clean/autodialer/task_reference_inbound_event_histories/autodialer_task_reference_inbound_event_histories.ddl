DROP TABLE datalake_clean.autodialer_task_reference_inbound_event_histories;

CREATE EXTERNAL TABLE datalake_clean.`autodialer_task_reference_inbound_event_histories`(
  `_class` string,
  `active` boolean,
  `address` string,
  `agentid` string,
  `assignee` string,
  `calltype` string,
  `callanalyzer` string,
  `class` string,
  `created_at` string,
  `dialstatus` string,
  `email` string,
  `eventdate` string,
  `hangupcause` string,
  `id` string,
  `index` bigint,
  `name` string,
  `phones` string,
  `score` string,
  `sipcause` string,
  `snoozed` string,
  `task_id` string,
  `tasklink` string,
  `taskreferenceeventorigin` string,
  `tasktype` string,
  `updated_at` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/autodialer/task_reference_inbound_event_histories/task_reference_inbound_event_histories/'

msck repair table datalake_clean.autodialer_task_reference_inbound_event_histories