drop table if exists datalake_heimdall_clean_prod.activity;
create external table if not exists datalake_heimdall_clean_prod.activity (
    id string,
    id_house bigint,
    id_external_contract bigint,
    class string,
    status string,
    type string,
    transition_list string,
    metadata string,
    ts_updated string,
    ts_created string
)
stored as parquet
location 's3://5a-datalake-prod/clean/heimdall/activity/'
tblproperties ("parquet.compress"="SNAPPY");