drop table if exists datalake_teravoz_clean_prod.ddrs;
create external table if not exists datalake_teravoz_clean_prod.ddrs (
    id integer,
    ts_activated timestamp,
    ts_activated_local timestamp,
    city_code tinyint,
    phone_number string,
    phone_number_prefix smallint,
    phone_number_suffix smallint,
    ts_load timestamp
)
partitioned by (
    year smallint,
    month tinyint,
    day tinyint
)
stored as parquet
location 's3://5a-datalake-prod/clean/teravoz/ddrs/'
tblproperties ("parquet.compress"="SNAPPY");