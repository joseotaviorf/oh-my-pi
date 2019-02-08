drop table if exists datalake_clean.killqueue_reservation_aud;

CREATE EXTERNAL TABLE datalake_clean.`killqueue_reservation_aud`(
  `id` string,
  `rev` string,
  `revtype` string,
  `revend` string,
  `attempt` string,
  `attempt_mod` string,
  `mundipagg_token` string,
  `mundipagg_token_mod` string,
  `rent_flow_id` string,
  `status` string,
  `status_mod` string,
  `tenant_id` string,
  `value` string,
  `value_mod` string,
  `house_id` string
)
STORED AS PARQUET LOCATION 's3://5a-datalake/clean/kill_queue/reservation_aud/';