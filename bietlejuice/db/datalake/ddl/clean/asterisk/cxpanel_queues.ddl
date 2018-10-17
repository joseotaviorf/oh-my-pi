drop table if exists datalake_clean.asterisk_cxpanel_queues;
create external table if not exists datalake_clean.asterisk_cxpanel_queues (
  cxpanel_queue_id string,
  queue_id string,
  display_name string,
  add_queue string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/cxpanel_queues/'
;