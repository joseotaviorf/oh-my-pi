drop table if exists datalake_raw.gsheet_dau_taxonomy_demand;

CREATE EXTERNAL TABLE datalake_raw.gsheet_dau_taxonomy_demand(
  category string,
  channel string,
  completion string,
  flow string,
  medium string,
  platform string,
  source string,
  app_type string,
  branded string,
  qnt string,
  utm_medium string,
  utm_source string)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"')
location
  's3://5a-datalake/raw/gsheet/dau_taxonomy_demand/'
tblproperties (
  'skip.header.line.count' = '1'
)
;