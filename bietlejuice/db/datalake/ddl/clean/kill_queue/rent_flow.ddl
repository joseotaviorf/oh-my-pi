drop table if exists datalake_clean.killqueue_rent_flow;

CREATE EXTERNAL TABLE datalake_clean.`killqueue_rent_flow`(
  `id`           string,
  `created_at`   string,
  `updated_at`   string,
  `version`      string,
  `firestore_id` string,
  `house_id`     string,
  `tenant_id`    string,
  `status`       string
)
STORED AS PARQUET LOCATION 's3://5a-datalake/clean/kill_queue/rent_flow/';