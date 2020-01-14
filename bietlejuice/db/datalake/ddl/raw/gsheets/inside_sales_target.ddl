drop table if exists datalake_raw.gsheets_inside_sales_target;

create external table datalake_raw.gsheets_inside_sales_target (
    canal string,
    id string,
    listing string,
    manager string,
    manager_id string,
    nome string,
    opportunity string,
    tl string,
    tl_id string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/gsheets/inside_sales_target/'
