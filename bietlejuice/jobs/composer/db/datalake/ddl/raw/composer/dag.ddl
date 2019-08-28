CREATE EXTERNAL TABLE `datalake_composer_raw_{ENV}.dag`
(
  `dag_id` string,
  `is_paused` boolean,
  `is_subdag` boolean,
  `is_active` boolean,
  `last_scheduler_run` string,
  `last_pickled` string,
  `last_expired` string,
  `scheduler_lock` boolean,
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