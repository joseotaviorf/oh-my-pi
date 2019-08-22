CREATE EXTERNAL TABLE `datalake_composer_raw_{ENV}.dag`
(
  `dag_id` string,
  `is_paused` string,
  `is_subdag` string,
  `is_active` string,
  `last_scheduler_run` string,
  `last_pickled` string,
  `last_expired` string,
  `scheduler_lock` string,
  `pickle_id` string,
  `fileloc` string,
  `owners` string,
  `description` string,
  `default_view` string,
  `schedule_interval` string
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
LOCATION
's3://5a-datalake-{ENV}/raw/composer/dag'
;