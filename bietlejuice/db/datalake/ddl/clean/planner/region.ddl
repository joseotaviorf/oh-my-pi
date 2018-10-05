drop table if exists datalake_clean.planner_region;
create external table if not exists datalake_clean.planner_region (
  visit string,
  slot_available boolean,
  slot_status string,
  slot_available_agents string,
  slot_id bigint,
  slot_time string
)
partitioned by (
  dt string,
  region string
)
stored as parquet
location 's3://5a-datalake/clean/planner/'
;
