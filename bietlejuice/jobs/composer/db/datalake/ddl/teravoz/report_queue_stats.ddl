drop table if exists datalake_teravoz_clean_prod.report_queue_stats;
create external table if not exists datalake_teravoz_clean_prod.report_queue_stats (
    queue_number integer,
    calls_abandoned integer,
    calls_answered integer,
    calls_received integer,
    calls_timed_out integer,
    dt_created date,
    ts_load timestamp
)
partitioned by (
    year smallint,
    month tinyint,
    day tinyint
)
stored as parquet
location 's3://5a-datalake-prod/clean/teravoz/report_queue_stats/'
tblproperties ("parquet.compress"="SNAPPY");