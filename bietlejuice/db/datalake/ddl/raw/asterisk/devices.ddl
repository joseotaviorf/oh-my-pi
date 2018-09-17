drop table if exists datalake_raw.asterisk_devices;
create external table if not exists datalake_raw.asterisk_devices (
  id string,
  tech string,
  dial string,
  devicetype string,
  user string,
  description string,
  emergency_cid string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/devices/'
;