CREATE EXTERNAL TABLE `datalake_composer_raw_{ENV}.task_fail`
(
  `id` string,
  `task_id` string,
  `dag_id` string,
  `execution_date` string,
  `start_date` string,
  `end_date` string,
  `duration` string
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
LOCATION
's3://5a-datalake-{ENV}/raw/composer/task_fail'
;