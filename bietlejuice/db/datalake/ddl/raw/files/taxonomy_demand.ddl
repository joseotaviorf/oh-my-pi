drop table if exists datalake_raw.taxonomy_demand;

create external table datalake_raw.taxonomy_demand (
  id string,
  app_type string,
  utm_source string,
  utm_medium string,
  branded string,
  first_update_source string,
  flg_via_reschedule string,
  mkt_category string,
  mkt_flow string,
  mkt_completion string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string,
  mkt_platform string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"',
  'mapping.mkt_category'='Category',
  'mapping.mkt_flow'='Flow',
  'mapping.mkt_completion'='Completion',
  'mapping.mkt_channel'='Channel',
  'mapping.mkt_medium'='Medium',
  'mapping.mkt_source'='Source',
  'mapping.mkt_platform'='Platform'
)
location 's3://5a-datalake/raw/gsheets/taxonomy_demand/'
tblproperties (
  'skip.header.line.count' = '1'
)
;