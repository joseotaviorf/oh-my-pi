drop table if exists datalake_raw.adjusted_visits_prediction;
create external table if not exists datalake_raw.adjusted_visits_prediction (
  region_code string,
  dt string,
  slot string,
  predicted_visits string
)
partitioned by (
  dt_predicted string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'mapping.dt'='day', 
  'mapping.predicted_visits'='prediction', 
  'mapping.region_code'='macro_region', 
  'quoteChar'='\"', 
  'separatorChar'=','
)
location 's3://5a-datalake/hekima/results/prediction/rf/visits_adjustment/historical'
tblproperties (
  'skip.header.line.count'='1'
);