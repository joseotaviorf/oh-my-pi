drop table if exists datalake_bigfone_clean_prod.events;
create external table if not exists datalake_bigfone_clean_prod.events (
    id bigint,
    id_call string,
    metadata string,
    ts_created timestamp,
    ts_created_local timestamp,
    ts_received timestamp,
    ts_received_local timestamp
)
partitioned by (
    year smallint,
    month smallint,
    day smallint,
    event string
)
stored as parquet
location 's3://5a-datalake-prod/clean/bigfone/events/'
tblproperties ("parquet.compress"="SNAPPY");