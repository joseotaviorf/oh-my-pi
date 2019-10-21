drop table if exists datalake_raw.sortinghat_screening_result;
create external table datalake_raw.sortinghat_screening_result (
  id string,
  score string,
  risk_category string,
  liquidity string,
  proposal_id string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/sorting_hat/ScreeningResult/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
