drop table if exists datalake_clean.killqueue_reservation;

CREATE EXTERNAL TABLE datalake_clean.`killqueue_reservation`(
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
STORED AS PARQUET LOCATION 's3://5a-datalake/clean/kill_queue/reservation/';