drop table if exists datalake_raw.gsheet_marketing_manual_costs_google;

create external table datalake_raw.gsheet_marketing_manual_costs_google (
  account_name string,
  campaign_name string,
  cost_date string,
  desktop_cost string,
  mobile_cost string,
  tablet_cost string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/gsheet/marketing_manual_costs_google/'
tblproperties (
  'skip.header.line.count' = '1'
)
;