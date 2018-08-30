drop table if exists datalake_raw.asterisk_ivr_details;
create external table if not exists datalake_raw.asterisk_ivr_details (
  id string,
  name string,
  description string,
  announcement string,
  directdial string,
  invalid_loops string,
  invalid_retry_recording string,
  invalid_destination string,
  timeout_enabled string,
  invalid_recording string,
  retvm string,
  timeout_time string,
  timeout_recording string,
  timeout_retry_recording string,
  timeout_destination string,
  timeout_loops string,
  timeout_append_announce string,
  invalid_append_announce string,
  timeout_ivr_ret string,
  invalid_ivr_ret string,
  alertinfo string,
  rvolume string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/ivr_details/'
;