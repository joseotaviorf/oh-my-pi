drop table if exists datalake_clean.asterisk_events;
create external table if not exists datalake_clean.asterisk_events (
    id_call string,
    id_stage string,
    desc_stage string,
    desc_event string,
    value_event string,
    time_ocurred string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/events/';