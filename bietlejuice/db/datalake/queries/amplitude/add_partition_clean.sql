alter table datalake_amplitude_clean_prod.events
  add if not exists partition (et='{et}', ym='{ym}')
    location 's3://{s3_bucket}/clean/amplitude/events/et={et}/ym={ym}'
