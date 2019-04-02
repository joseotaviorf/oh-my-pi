drop table if exists datalake_raw.sortinghat_external_score;
create external table datalake_raw.sortinghat_external_score (
  id string,
  cpf string,
  source string,
  value string,
  created_at string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/sorting_hat/ExternalScore/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
