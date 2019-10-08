drop table if exists datalake_teravoz_clean_prod.queues;
create external table if not exists datalake_teravoz_clean_prod.queues (
    id integer,
    number smallint,
    name string,
    agents_logged smallint,
    ts_load timestamp
)
partitioned by (
    year smallint,
    month tinyint,
    day tinyint
)
stored as parquet
location 's3://5a-datalake-prod/clean/teravoz/queues/'
tblproperties ("parquet.compress"="SNAPPY");