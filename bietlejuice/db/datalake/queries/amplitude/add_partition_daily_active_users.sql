alter table datalake_clean.amplitude_daily_active_users
  add if not exists partition (app='{app}', ym='{ym}')
    location 's3://{s3_bucket}/clean/amplitude/daily_active_users/app={app}/ym={ym}'
