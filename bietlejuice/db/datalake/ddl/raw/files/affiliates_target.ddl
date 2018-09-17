drop table if exists datalake_raw.affiliates_target;

create external table datalake_raw.affiliates_target (
  day string,
  indicaai_target_listings string,
  doorman_target_listings string,
  indicaai_target_leads string,
  doorman_target_leads string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"',
  'mapping.day'='Day',
  'mapping.indicaai_target_listings'='IndicaAi target listings',
  'mapping.doorman_target_listings'='Doorman target listings',
  'mapping.indicaai_target_leads'='IndicaAi target leads',
  'mapping.doorman_target_leads'='Doorman target leads'
)
location 's3://5a-datalake/raw/files/affiliates_target/'
tblproperties (
  'skip.header.line.count' = '1'
)
;