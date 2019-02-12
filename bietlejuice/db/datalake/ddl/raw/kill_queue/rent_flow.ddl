drop table if exists datalake_raw.killqueue_rent_flow;

CREATE EXTERNAL TABLE datalake_raw.`killqueue_rent_flow`(
  `id`           string,
  `created_at`   string,
  `updated_at`   string,
  `version`      string,
  `firestore_id` string,
  `house_id`     string,
  `tenant_id`    string,
  `status`       string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://5a-datalake/raw/kill_queue/rent_flow/';