drop table if exists datalake_raw.visits_conversion;
create external table if not exists datalake_raw.visits_conversion (
  region_code string,
  day_of_week string,
  visit_hour string,
  conversion_booking_to_visit string
)
partitioned by (
  dt_calculated string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'mapping.day_of_week'='dow',
  'quoteChar'='\"',
  'separatorChar'=','
)
location 's3://5a-datalake/hekima/results/prediction/rf/visits_conversion/historical'
tblproperties (
  'skip.header.line.count'='1'
);