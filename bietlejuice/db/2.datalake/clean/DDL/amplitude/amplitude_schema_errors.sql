drop table datalake_clean.amplitude_schema_errors;
create external table datalake_clean.amplitude_schema_errors (
  app_id string,
  event_type string,
  uuid string,
  server_upload_time string,
  platform string,
  validation_time string,
  err_path string,
  err_validator string,
  err_validator_value string,
  err_instance string,
  err_details string,
  validation_status string
)
partitioned by (
  ym string,
  et string
)
stored as parquet
location 's3://5a-datalake/clean/amplitude/event_errors/'
;

-- warning: do not load all partitions (msck repair table)