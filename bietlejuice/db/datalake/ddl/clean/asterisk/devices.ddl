drop table if exists datalake_clean.asterisk_devices;
create external table if not exists datalake_clean.asterisk_devices (
  id integer,
  tech string,
  dial string,
  device_type string,
  user_id integer,
  description string,
  emergency_cid float
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/devices/'
;