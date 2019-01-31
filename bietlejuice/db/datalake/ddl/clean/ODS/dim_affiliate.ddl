drop table if exists datalake_clean.ods_dim_affiliate;
create external table if not exists datalake_clean.ods_dim_affiliate (
    sk_affiliate string,
    id_affiliate string,
    ts_joined_program string,
    category string,
    work_city string,
    is_active string,
    ts_updated string,
    ts_created string,
    creci_number string,
    origin string,
    type string,
    ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/affiliate'
tblproperties (
  'skip.header.line.count' = '1'
)
;