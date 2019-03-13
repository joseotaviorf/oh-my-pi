alter table datalake_clean.amplitude_active_user_sessions
  add if not exists partition (app='{app}', ym='{ym}')
    location 's3://{s3_bucket}/clean/amplitude/active_user_sessions/app={app}/ym={ym}'
