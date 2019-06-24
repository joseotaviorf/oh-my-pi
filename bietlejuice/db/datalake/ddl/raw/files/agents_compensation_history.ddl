drop table if exists datalake_raw.agents_compensation_history;

create external table datalake_raw.agents_compensation_history (
    `1_contract` float,
    `2_contract` float,
    `3_contract` float,
    `4_contract` float,
    `5_contract` float,
    `6_contract` float,
    `7_contract` float,
    `init` date,
    `end` date,
    `region_code` string
)
COMMENT 'from google sheets [Agents Compensation] file  and [Historico de Comissoes] sheet in link  https://docs.google.com/spreadsheets/d/1e3588dE7amznUtmUCTZ6GZDZQkKPvrMq1XsLMoiT-6g/ '
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/files/agents_compensation/'
tblproperties (
  'skip.header.line.count' = '1'
)
;