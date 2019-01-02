drop table if exists datalake_clean.agent_contract_type;

create external table datalake_clean.agent_contract_type (
  id string,
  slots_per_saturday string,
  slots_per_weekday string,
  contract_name string,
  contract_type string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/files/agent_contract_type/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
