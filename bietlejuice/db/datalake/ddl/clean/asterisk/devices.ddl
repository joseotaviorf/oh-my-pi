drop table if exists datalake_clean.asterisk_devices;
create external table if not exists datalake_clean.asterisk_devices (
  id string,
  tech string,
  dial string,
  device_type string,
  user_id string,
  description string,
  emergency_cid string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/devices/'
;