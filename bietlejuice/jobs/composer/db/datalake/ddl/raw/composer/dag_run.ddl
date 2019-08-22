CREATE EXTERNAL TABLE `datalake_composer_raw_{ENV}.dag_run`
(
  `id` string,
  `dag_id` string,
  `execution_date` string,
  `state` string,
  `run_id` string,
  `external_trigger` string,
  `conf` string,
  `end_date` string,
  `start_date` string
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
LOCATION
's3://5a-datalake-{ENV}/raw/composer/dag_run'
;