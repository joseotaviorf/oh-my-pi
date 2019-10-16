drop table if exists datalake_teravoz_clean_prod.calls;
create external table if not exists datalake_teravoz_clean_prod.calls (
    id string,
    ts_started timestamp,
    ts_started_local timestamp,
    called_phone_number string,
    caller_phone_number string,
    destination_called_number string,
    caller_phone_type string,
    price float,
    source_caller_number string,
    seconds_talk_duration smallint,
    status string,
    call_direction string,
    ts_load timestamp
)
partitioned by (
    year smallint,
    month tinyint,
    day tinyint
)
stored as parquet
location 's3://5a-datalake-prod/clean/teravoz/calls/'
tblproperties ("parquet.compress"="SNAPPY");