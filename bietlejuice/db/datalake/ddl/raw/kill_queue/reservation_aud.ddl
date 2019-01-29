drop table if exists datalake_raw.killqueue_reservation_aud;

CREATE EXTERNAL TABLE datalake_raw.`killqueue_reservation_aud`(
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
  `house_id` string,
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://5a-datalake/raw/kill_queue/reservation_aud/';