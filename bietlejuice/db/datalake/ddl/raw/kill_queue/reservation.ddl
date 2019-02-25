drop table if exists datalake_raw.killqueue_reservation;

CREATE EXTERNAL TABLE datalake_raw.`killqueue_reservation`(
  `id`              string,
  `created_at`      string,
  `updated_at`      string,
  `version`         string,
  `attempt`         string,
  `rent_flow_id`    string,
  `status`          string,
  `tenant_id`       string,
  `value`           string,
  `house_id`        string,
  `mundipagg_token` string,
  `is_ongoing`      string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://5a-datalake/raw/kill_queue/reservation/';