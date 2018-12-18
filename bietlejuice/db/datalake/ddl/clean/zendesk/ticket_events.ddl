drop table datalake_clean.`zendesk_ticket_events`;

CREATE EXTERNAL TABLE datalake_clean.`zendesk_ticket_events`(
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
  `dt_extraction` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/zendesk/ticket_events'
  ;

msck repair table datalake_clean.`zendesk_ticket_events`;