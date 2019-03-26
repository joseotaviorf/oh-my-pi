alter table datalake_raw.amplitude_active_user_sessions
  add if not exists partition (dt='{dt}')
    location 's3://{s3_bucket}/raw/amplitude/active_user_sessions/dt={dt}'
