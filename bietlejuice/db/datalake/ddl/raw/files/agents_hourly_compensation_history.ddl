drop table if exists datalake_raw.agents_hourly_compensation_history;

create external table datalake_raw.agents_hourly_compensation_history (
    `commission` float,
    `end` date,
    `init` date,
    `region_code` string
)
COMMENT 'from google sheets [Agents Compensation] file  and [Historico de Comissoes por hora] sheet'
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/files/agents_hourly_compensation/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
