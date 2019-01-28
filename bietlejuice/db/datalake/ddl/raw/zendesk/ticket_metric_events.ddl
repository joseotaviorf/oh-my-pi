drop table datalake_raw.zendesk_ticket_metric_events;

CREATE EXTERNAL TABLE datalake_raw.`zendesk_ticket_metric_events`(
  `id` string,
  `ticket_id` string,
  `metric` string,
  `instance_id` string,
  `type` string,
  `status` string,
  `time` string,
  `sla` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/zendesk/ticket_metric_events/'
;

msck repair table datalake_raw.zendesk_ticket_metric_events;