drop table if exists datalake_clean.ods_dim_partner_agent;
create external table if not exists datalake_clean.ods_dim_partner_agent (
    sk_partner_agent string,
    id_partner_agent string,
    status_partner_agent string, 
    id_user string,
    id_partner string,
    type string,
    ts_updated string,
    ts_created string,
    ts_load string
)

row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)

location 's3://5a-datalake/clean/ods/partner_agent'
tblproperties (
  'skip.header.line.count' = '1'
);
