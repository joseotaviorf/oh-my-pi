alter table datalake_raw.amplitude_events
  drop if exists partition (dt='{0}')