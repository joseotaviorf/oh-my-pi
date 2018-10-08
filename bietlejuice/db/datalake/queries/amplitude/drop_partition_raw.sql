alter table datalake_raw.amplitude_events
  drop if exists partition (dt='{dt_partition}')