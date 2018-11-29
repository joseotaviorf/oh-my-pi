DROP TABLE datalake_raw.task_reference_outbound_event_histories;

CREATE EXTERNAL TABLE datalake_raw.task_reference_outbound_event_histories (
  `_class` string,
  `_id` string,
  `createdAt` string,
  `taskId` string,
  `taskReferenceOutboundEvents` string,
  `updatedAt` string)
PARTITIONED BY (
  `dt` string)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';'
)
LOCATION
  's3://5a-datalake/raw/autodialer/task_reference_outbound_event_histories/'
TBLPROPERTIES (
  'skip.header.line.count'='1');

msck repair table datalake_raw.task_reference_outbound_event_histories;