drop table if exists datalake_clean.asterisk_events;
create external table if not exists datalake_clean.asterisk_events (
  id_call string,
  id_phase string,
  phase string,
  name string,
  params string,
  ts_created string,
  ts_load string
)
partitioned by (
  dt string,
  event string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/events/';