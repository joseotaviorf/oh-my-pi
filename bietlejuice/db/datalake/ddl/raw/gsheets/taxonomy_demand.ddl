drop table if exists datalake_raw.gsheets_taxonomy_demand;

create external table datalake_raw.gsheets_taxonomy_demand (
    app_type string,
    branded string,
    category string,
    channel string,
    completion string,
    first_update_source string,
    flg_via_reschedule string,
    flow string,
    id string,
    medium string,
    platform string,
    source string,
    utm_medium string,
    utm_source string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
    'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/gsheets/taxonomy_demand/'
;
