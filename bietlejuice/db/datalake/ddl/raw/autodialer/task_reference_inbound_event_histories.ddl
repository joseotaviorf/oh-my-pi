DROP TABLE datalake_raw.autodialer_task_reference_inbound_event_histories;

CREATE EXTERNAL TABLE datalake_raw.autodialer_task_reference_inbound_event_histories (
  `_class` string,
  `_id` string,
  `createdAt` string,
  `inboundEvents` array<string>,
  `taskId` string,
  `updatedAt` string)
PARTITIONED BY (
  dt_extraction string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
LOCATION
  's3://5a-datalake/raw/autodialer/task_reference_inbound_event_histories/'

msck repair table datalake_raw.autodialer_task_reference_inbound_event_histories;
