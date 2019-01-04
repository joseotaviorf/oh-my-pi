DROP TABLE datalake_clean.autodialer_task_references;

CREATE EXTERNAL TABLE datalake_clean.`autodialer_task_references`(
  `id` string,
  `class` string,
  `active` boolean,
  `agent_id` integer,
  `assignee` string,
  `auto_dialer_response` string,
  `created_date` string,
  `score` integer,
  `snoozed_until` string,
  `task_id` string,
  `task_link` string,
  `task_type` string,
  `updated_date` string,
  `contactdidnotanswercounter` string)
PARTITIONED BY (
  `dt_extraction` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/autodialer/task_references/'

msck repair table datalake_clean.autodialer_task_references