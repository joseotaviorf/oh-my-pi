drop table datalake_raw.amplitude_events;
create external table datalake_raw.amplitude_events (
  event_data string
)
partitioned by (
  dt string
)
stored as textfile
location 's3://5a-datalake/raw/amplitude/events'
;

-- warning: do not load all partitions (msck repair table)
