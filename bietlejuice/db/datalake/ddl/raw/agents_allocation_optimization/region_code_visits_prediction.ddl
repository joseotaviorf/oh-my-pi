drop table if exists datalake_raw.region_code_visits_prediction;
create external table if not exists datalake_raw.region_code_visits_prediction (
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
  'quoteChar'='\"',
  'separatorChar'=',',
  'mapping.region_code'='macro_region' ,
  'mapping.dt'='day',
  'mapping.predicted_visits'='prediction'
)
location 's3://5a-datalake/hekima/results/prediction/rf/historical/'
tblproperties (
  'skip.header.line.count'='1'
)
;
