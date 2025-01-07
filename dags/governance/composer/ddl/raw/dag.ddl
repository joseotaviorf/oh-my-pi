CREATE EXTERNAL TABLE IF NOT EXISTS `{DATABASE}.dag`
(
  `dag_id` string,
  `is_paused` tinyint,
  `is_subdag` tinyint,
  `is_active` tinyint,
  `last_scheduler_run` string,
  `last_pickled` string,
  `last_expired` string,
  `scheduler_lock` tinyint,
  `pickle_id` int,
  `fileloc` string,
  `owners` string,
  `description` string,
  `default_view` string,
  `schedule_interval` string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION
's3://{BUCKET}/raw/composer/dag'
;