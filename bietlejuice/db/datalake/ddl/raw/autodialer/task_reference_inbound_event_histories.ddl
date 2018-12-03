DROP TABLE datalake_raw.task_reference_inbound_event_histories;

CREATE EXTERNAL TABLE datalake_raw.task_reference_inbound_event_histories (
  `_class` string,
  `_id` string,
  `createdAt` string,
  `inboundEvents` array<string>,
  `taskId` string,
  `updatedAt` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
LOCATION
  's3://5a-datalake/raw/autodialer/task_reference_inbound_event_histories/'
TBLPROPERTIES (
  'skip.header.line.count'='1');

msck repair table datalake_raw.task_reference_inbound_event_histories;
