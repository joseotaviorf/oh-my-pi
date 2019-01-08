DROP TABLE datalake_raw.autodialer_task_reference_outbound_event_histories;

CREATE EXTERNAL TABLE datalake_raw.autodialer_task_reference_outbound_event_histories(
  `_id` string,
  taskReferenceOutboundEvents array<string>,
  taskId string,
  updatedAt string,
  `_class` string,
  createdAt string)
PARTITIONED BY (
  dt_extraction string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
LOCATION
  's3://5a-datalake/raw/autodialer/task_reference_outbound_event_histories/'

msck repair table datalake_raw.autodialer_task_reference_outbound_event_histories;