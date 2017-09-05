alter table datalake_raw.amplitude_events
  add if not exists partition (dt='{0}')
    location 's3://{1}/raw/amplitude/events/dt={0}'