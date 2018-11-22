drop table if exists datalake_raw.daylight_saving_time_periods;

create external table datalake_raw.daylight_saving_time_periods (
  date_start string,
  date_end string,
  time_diff string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"',
  'mapping.date_start'='dti',
  'mapping.date_end'='dtf',
  'mapping.time_diff'='timediff'
)
location 's3://5a-datalake/raw/files/daylight_saving_time_periods/'
tblproperties (
  'skip.header.line.count' = '1'
)
;