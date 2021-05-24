drop table if exists datalake_clean.ods_dim_partner;
create external table if not exists datalake_clean.ods_dim_partner (
    sk_partner string,
    id_partner string,
    id_amplitude_device string,
    name string,
    trade_name string,
    phone string,
    email string,
    cnpj string,
    creci string,
    type string,
    city string,
    ts_joined_partnership string,
    ts_updated string,
    ts_created string,
    ts_load string
)

row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)

location 's3://5a-datalake/clean/ods/partner'
tblproperties (
  'skip.header.line.count' = '1'
);
