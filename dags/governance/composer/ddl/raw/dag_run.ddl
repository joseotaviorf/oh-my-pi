CREATE EXTERNAL TABLE IF NOT EXISTS `{DATABASE}.dag_run`
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
's3://{BUCKET}/raw/composer/dag_run'
;