drop table if exists datalake_raw.asterisk_queues_details;
create external table if not exists datalake_raw.asterisk_queues_details (
  id string,
  keyword string,
  data string,
  flags string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/queues_details/'
;