alter table datalake_clean.amplitude_events
  add if not exists partition (et='{0}', ym='{1}')
    location 's3://{2}/clean/amplitude/events/et={0}/ym={1}'