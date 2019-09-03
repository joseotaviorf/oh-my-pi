CREATE EXTERNAL TABLE `datalake_composer_raw_{ENV}.task_fail`
(
  `id` int,
  `task_id` string,
  `dag_id` string,
  `execution_date` string,
  `start_date` string,
  `end_date` string,
  `duration` int
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION
's3://5a-datalake-{ENV}/raw/composer/task_fail'
;