alter table datalake_amplitude_raw_prod.events
  drop if exists partition (dt='{dt_partition}')