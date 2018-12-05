drop table if exists datalake_raw.weekly_targets;

create external table datalake_raw.weekly_targets (
  week_start_date string,
  city string,
  channel string,
  medium string,
  opportunity_target string,
  listing_target string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"',
  'mapping.week_start_date'='Data',
  'mapping.city'='Cidade',
  'mapping.channel'='Channel',
  'mapping.medium'='Medium',
  'mapping.opportunity_target'='Opportunity',
  'mapping.listing_target'='Listing'
)
location 's3://5a-datalake/raw/files/weekly_target/'
tblproperties (
  'skip.header.line.count' = '1'
)
;