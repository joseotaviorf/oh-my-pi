drop table if exists datalake_clean.asterisk_ivr_details;
create external table if not exists datalake_clean.asterisk_ivr_details (
  id integer,
  name string,
  description string,
  announcement integer,
  direct_dial string,
  invalid_loops string,
  invalid_retry_recording string,
  invalid_destination string,
  timeout_enabled string,
  invalid_recording string,
  retvm string,
  timeout_time integer,
  timeout_recording string,
  timeout_retry_recording string,
  timeout_destination string,
  timeout_loops string,
  timeout_append_announce integer,
  invalid_append_announce integer,
  timeout_ivr_ret integer,
  invalid_ivr_ret integer,
  alert_info string,
  r_volume string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/ivr_details/'
;