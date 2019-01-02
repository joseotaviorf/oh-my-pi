drop table datalake_raw.`zendesk_ticket_events`;

CREATE EXTERNAL TABLE datalake_raw.`zendesk_ticket_events`(
  `metadata` string,
  `system` string,
  `event_type` string,
  `updater_id` string,
  `created_at` string,
  `child_events` string,
  `id` string,
  `ticket_id` string,
  `timestamp` string,
  `via` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/zendesk/ticket_events'
  ;

msck repair table datalake_raw.`zendesk_ticket_events`;