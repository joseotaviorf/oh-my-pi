drop table if exists datalake_clean.ods_dim_user_doorman;
create external table if not exists datalake_clean.ods_dim_user_doorman (
    sk_user_doorman string,
    id_user_doorman string,
    work_address string,
    work_house_number string,
    work_neighbourhood string,
    work_city string,
    code string,
    ts_updated string,
    ts_created string,
    ts_joined_program string,
    sk_user_affiliate bigint,
    ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/user_doorman'
tblproperties (
  'skip.header.line.count' = '1'
)
;