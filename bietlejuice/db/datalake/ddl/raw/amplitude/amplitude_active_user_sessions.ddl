drop table datalake_raw.amplitude_active_user_sessions;

CREATE EXTERNAL TABLE datalake_raw.amplitude_active_user_sessions (
  event_date string,
  server_upload_time string,
  session_start_ts string,
  amplitude_id string,
  session_id string,
  country string,
  city string,
  region string,
  platform string,
  utm_source string,
  utm_medium string,
  utm_campaign string,
  utm_content string,
  utm_term string,
  event_type string,
  app string)
partitioned by (
  dt string)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
LOCATION
  's3://5a-datalake/raw/amplitude/active_user_sessions/'
TBLPROPERTIES (
  'skip.header.line.count'='1')