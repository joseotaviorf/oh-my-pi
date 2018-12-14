drop table datalake_clean.zendesk_ticket_metric_events;

CREATE EXTERNAL TABLE datalake_clean.`zendesk_ticket_metric_events`(
  `id` string,
  `ticket_id` string,
  `metric` string,
  `instance_id` string,
  `type` string,
  `time` string,
  `sla` string)
PARTITIONED BY (
  `dt` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/zendesk/ticket_metric_events/'
;

msck repair table datalake_clean.zendesk_ticket_metric_events;