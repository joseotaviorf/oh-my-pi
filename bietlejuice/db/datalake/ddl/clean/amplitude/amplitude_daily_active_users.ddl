drop table datalake_clean.amplitude_daily_active_users;

CREATE EXTERNAL TABLE datalake_clean.amplitude_daily_active_users(
  index bigint,
  event_date string,
  amplitude_id string,
  session_id string,
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
  mkt_channel string,
  mkt_medium string,
  mkt_source string,
  mkt_platform string)
partitioned by (
  app string, 
  ym string)
stored as parquet
location 's3://5a-datalake/clean/amplitude/daily_active_users/';

msck repair table datalake_clean.amplitude_daily_active_users;
