drop table if exists datalake_raw.agent_contract_hours;

create external table datalake_raw.agent_contract_hours (
    id string,
    contract_type string,
    contract_name string,
    weekday_08 string,
    weekday_09 string,
    weekday_10 string,
    weekday_11 string,
    weekday_12 string,
    weekday_13 string,
    weekday_14 string,
    weekday_15 string,
    weekday_16 string,
    saturday_09 string,
    saturday_10 string,
    saturday_11 string,
    saturday_12 string,
    saturday_13 string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/files/agent_contract_hours_detailed/'
tblproperties (
  'skip.header.line.count' = '1'
)
;