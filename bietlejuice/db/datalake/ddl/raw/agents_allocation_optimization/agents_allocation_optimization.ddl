drop table if exists datalake_raw.agents_allocation_optimization;
create external table if not exists datalake_raw.agents_allocation_optimization (
  region_code string,
  prediction_hour string,
  dt string,
  hour string,
  slots string,
  visits string,
  worst_case_agents string,
  unique_agents_hour string,
  new_agents string,
  available_agents string,
  release_schedule string
)
partitioned by (
  dt_predicted string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'mapping.dt'='date',
  'mapping.region_code'='region_macro',
  'quoteChar'='\"',
  'separatorChar'=','
)
location 's3://5a-datalake/hekima/optimization_result/historical'
tblproperties (
  'skip.header.line.count'='1'
)
;