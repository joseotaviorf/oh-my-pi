drop table if exists datalake_raw.agent_contract_hours;

create external table datalake_raw.agent_contract_hours (
    contract_name string,
    contract_type string,
    id string,
    is_saturday_available_at_09 string,
    is_saturday_available_at_10 string,
    is_saturday_available_at_11 string,
    is_saturday_available_at_12 string,
    is_saturday_available_at_13 string,
    is_weekday_available_at_08 string,
    is_weekday_available_at_09 string,
    is_weekday_available_at_10 string,
    is_weekday_available_at_11 string,
    is_weekday_available_at_12 string,
    is_weekday_available_at_13 string,
    is_weekday_available_at_14 string,
    is_weekday_available_at_15 string,
    is_weekday_available_at_16 string
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