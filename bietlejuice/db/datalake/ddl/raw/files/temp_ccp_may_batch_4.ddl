drop table if exists datalake_raw.temp_ccp_may_batch_4;

create external table datalake_raw.temp_ccp_may_batch_4 (
  external_id integer,
  first_name string,
  email string,
  url_ccp string,
  batch string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake-prod/raw/files/temp_ccp_may_batch_4/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
