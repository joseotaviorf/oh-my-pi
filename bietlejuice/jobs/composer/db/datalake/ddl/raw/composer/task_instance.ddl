CREATE EXTERNAL TABLE IF NOT EXISTS `{DATABASE}.task_instance`
(
  `task_id` string,
  `dag_id` string,
  `state` string,
  `duration` float,
  `max_tries` int,
  `try_number` int,
  `end_date` string,
  `execution_date` string,
  `start_date` string
)
PARTITIONED BY ( 
  `year` int, 
  `month` int, 
  `day` int)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION
's3://{BUCKET}/raw/composer/task_instance'
;