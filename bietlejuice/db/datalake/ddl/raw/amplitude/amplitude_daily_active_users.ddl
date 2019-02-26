drop table datalake_raw.amplitude_daily_active_users;

CREATE EXTERNAL TABLE datalake_raw.amplitude_daily_active_users (
  event_date string,
  session_start_ts string,
  amplitude_id bigint,
  session_id bigint,
  country string,
  city string,
  region string,
  platform string,
  utm_source string,
  utm_medium string,
  utm_campaign string,
  utm_content string,
  utm_term string,
  app string)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
LOCATION
  's3://5a-datalake/raw/amplitude/daily_active_users/'
TBLPROPERTIES (
  'skip.header.line.count'='1')