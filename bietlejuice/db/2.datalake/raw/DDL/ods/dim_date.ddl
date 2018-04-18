drop table datalake_raw.dim_date;

CREATE external TABLE datalake_raw.dim_date (
  sk_date STRING,
  date STRING,
  year STRING ,
  month STRING,
  month_name STRING,
  day STRING,
  day_of_year STRING,
  week_day STRING,
  weekday_name STRING,
  calendar_week STRING,
  brz_date STRING,
  usa_date STRING,
  universal_date STRING,
  quarter STRING,
  year_quarter STRING,
  year_month STRING,
  year_calendar_week STRING,
  weekend STRING,
  is_brz_holiday STRING,
  brz_season STRING,
  week_start STRING,
  week_end STRING,
  month_start STRING,
  month_end STRING,
  last_day STRING,
  last_week STRING,
  last_2_weeks STRING,
  last_4_weeks STRING,
  last_month STRING,
  last_quarter STRING,
  last_year STRING
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/ods/dim_date/'
;