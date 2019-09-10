CREATE EXTERNAL TABLE `datalake_composer_raw_{ENV}.dag`
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
's3://5a-datalake-{ENV}/raw/composer/dag'
;