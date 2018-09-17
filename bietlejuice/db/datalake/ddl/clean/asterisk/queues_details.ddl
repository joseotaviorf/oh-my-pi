drop table if exists datalake_clean.asterisk_queues_details;
create external table if not exists datalake_clean.asterisk_queues_details (
  id integer,
  keyword string,
  data string,
  flags integer
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/queues_details/'
;