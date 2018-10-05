alter table datalake_raw.amplitude_events
  add if not exists partition (dt='{dt_partition}')
    location 's3://{s3_bucket}/raw/amplitude/events/dt={dt_partition}'