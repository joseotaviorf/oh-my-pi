drop table datalake_clean.amplitude_active_user_sessions;

CREATE EXTERNAL TABLE datalake_clean.amplitude_active_user_sessions (
  dt_event string,
  ts_server_upload string,
  id_amplitude string,
  id_session string,
  city string,
  region string,
  platform string,
  utm_source string,
  utm_medium string,
  utm_campaign string,
  utm_content string,
  utm_term string,
  mkt_category string,
  mkt_flow string,
  mkt_completion string,
  mkt_origin string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string,
  mkt_platform string)
partitioned by (
  app string, 
  ym string)
stored as parquet
location 's3://5a-datalake/clean/amplitude/active_user_sessions/';

msck repair table datalake_clean.amplitude_active_user_sessions;
