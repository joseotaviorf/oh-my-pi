drop table if exists datalake_raw.taxonomy_mkt_cost;

create external table datalake_raw.taxonomy_mkt_cost (
    account_name string,
    fact_cost string,
    fator_custo string,
    mkt_category string,
    mkt_channel string,
    mkt_completion string,
    mkt_flow string,
    mkt_medium string,
    mkt_platform string,
    mkt_source string,
    origin string,
    schema string,
    side string,
    split_into_cities string,
    table_dim string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/files/taxonomy_mkt_cost/'
tblproperties (
  'skip.header.line.count' = '1'
)
;