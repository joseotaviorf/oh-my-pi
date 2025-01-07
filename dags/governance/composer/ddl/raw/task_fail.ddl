CREATE EXTERNAL TABLE IF NOT EXISTS `{DATABASE}.task_fail`
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
's3://{BUCKET}/raw/composer/task_fail'
;