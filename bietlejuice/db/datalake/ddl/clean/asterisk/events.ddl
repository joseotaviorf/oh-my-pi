drop table if exists datalake_clean.asterisk_events;
create external table if not exists datalake_clean.asterisk_events (
  id_call string,
  id_stage string,
  stage string,
  name string,
  params string,
  ts_time_ocurred string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/events/';