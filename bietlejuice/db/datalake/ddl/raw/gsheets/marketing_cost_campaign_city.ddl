drop table if exists datalake_raw.gsheets_marketing_cost_campaign_city;

create external table datalake_raw.gsheets_marketing_cost_campaign_city (
    account_name string,
    campaign_name string,
    city_group string,
    side string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/gheets/marketing_cost_campaign_city/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
