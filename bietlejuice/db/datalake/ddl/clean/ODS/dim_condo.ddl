drop table if exists datalake_clean.ods_dim_condo;
create external table if not exists datalake_clean.ods_dim_condo (
    sk_condo string,
    id_condo string,
    neighborhood string,
    zipcode string,
    city string,
    address string,
    lat string,
    lng string,
    name string,
    number string,  
    ts_created string,
    ts_updated string,
    ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/condo'
tblproperties (
  'skip.header.line.count' = '1'
)
;