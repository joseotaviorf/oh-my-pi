drop table if exists datalake_teravoz_clean_prod.peers;
create external table if not exists datalake_teravoz_clean_prod.peers (
    is_active boolean,
    area_code tinyint,
    email string,
    name string,
    extension_number integer,
    ts_load timestamp
)
partitioned by (
    year smallint,
    month tinyint,
    day tinyint
)
stored as parquet
location 's3://5a-datalake-prod/clean/teravoz/peers/'
tblproperties ("parquet.compress"="SNAPPY");