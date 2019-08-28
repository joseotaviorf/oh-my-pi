CREATE EXTERNAL TABLE `datalake_composer_raw_{ENV}.dag_run`
(
  `id` int,
  `dag_id` string,
  `execution_date` string,
  `state` string,
  `run_id` string,
  `external_trigger` tinyint,
  `conf` varchar(65535),
  `end_date` string,
  `start_date` string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION
's3://5a-datalake-{ENV}/raw/composer/dag_run'
;