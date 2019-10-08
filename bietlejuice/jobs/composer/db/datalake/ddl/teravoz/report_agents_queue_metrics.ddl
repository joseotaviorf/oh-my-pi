drop table if exists datalake_teravoz_clean_prod.report_agents_queue_metrics;
create external table if not exists datalake_teravoz_clean_prod.report_agents_queue_metrics (
    extension_number smallint,
    queue_number smallint,
    agent_name string,
    hours_available_agent float,
    hours_agent_logged_out float,
    hours_agent_logged float,
    hours_agent_paused float,
    hours_agent_talked float,
    calls_answered smallint,
    calls_missed smallint,
    seconds_average_service_time integer,
    seconds_maximum_service_time integer,
    seconds_minimum_service_time integer,
    ts_load timestamp
)
partitioned by (
    year smallint,
    month tinyint,
    day tinyint
)
stored as parquet
location 's3://5a-datalake-prod/clean/teravoz/report_agents_queue_metrics/'
tblproperties ("parquet.compress"="SNAPPY");