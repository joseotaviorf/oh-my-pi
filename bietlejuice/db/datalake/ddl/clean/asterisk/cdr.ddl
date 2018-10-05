drop table if exists datalake_clean.asterisk_cdr;
create external table if not exists datalake_clean.asterisk_cdr (
  call_date string,
  cl_id string,
  src string,
  destination string,
  d_context string,
  channel string,
  dst_channel string,
  last_app string,
  last_data string,
  duration string,
  bill_sec string,
  disposition string,
  ama_flags string,
  account_code string,
  unique_id string,
  user_field string,
  d_id string,
  recording_file string,
  caller_number string,
  caller_name string,
  outbound_caller_number string,
  outbound_caller_name string,
  dst_cnam string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/cdr/'
;