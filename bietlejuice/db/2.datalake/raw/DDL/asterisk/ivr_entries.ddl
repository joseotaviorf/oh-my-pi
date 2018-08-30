drop table if exists datalake_raw.asterisk_ivr_entries;
create external table if not exists datalake_raw.asterisk_ivr_entries (
  ivr_id string,
  selection string,
  dest string,
  ivr_ret string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/ivr_entries/'
;