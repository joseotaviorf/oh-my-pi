drop table if exists datalake_raw.asterisk_cxpanel_queues;
create external table if not exists datalake_raw.asterisk_cxpanel_queues (
  cxpanel_queue_id string,
  queue_id string,
  display_name string,
  add_queue string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/cxpanel_queues/'
;