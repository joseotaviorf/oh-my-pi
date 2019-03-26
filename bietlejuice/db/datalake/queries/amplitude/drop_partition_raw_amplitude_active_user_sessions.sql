alter table datalake_raw.amplitude_active_user_sessions
  drop if exists partition (dt='{dt}')