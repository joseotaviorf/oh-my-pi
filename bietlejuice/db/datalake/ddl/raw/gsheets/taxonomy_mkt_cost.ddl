drop table if exists datalake_raw.gsheets_taxonomy_mkt_cost;

create external table datalake_raw.gsheets_taxonomy_mkt_cost (
    account_name string,
    campaign_origin_aquisition string,
    fact_cost string,
    mkt_category string,
    mkt_channel string,
    mkt_completion string,
    mkt_flow string,
    mkt_medium string,
    mkt_source string,
    mkt_origin string,
    origin string,
    schema string,
    side string,
    split_into_cities string,
    table_dim string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
    'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/gsheets/taxonomy_mkt_cost/'
;