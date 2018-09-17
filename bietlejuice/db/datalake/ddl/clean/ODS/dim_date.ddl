drop table if exists datalake_clean.ods_dim_date;
create external table datalake_clean.ods_dim_date (
  sk_date string,
  `date` string,
  year string,
  month string,
  month_name string,
  day string,
  day_of_year string,
  week_day string,
  weekday_name string,
  calendar_week string,
  brz_date string,
  usa_date string,
  universal_date string,
  quarter string,
  year_quarter string,
  year_month string,
  year_calendar_week string,
  weekend string,
  is_brz_holiday string,
  brz_season string,
  week_start string,
  week_end string,
  month_start string,
  month_end string,
  last_day string,
  last_week string,
  last_2_weeks string,
  last_4_weeks string,
  last_month string,
  last_quarter string,
  last_year string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/dim_date'
tblproperties (
  'skip.header.line.count' = '1'
)
;