drop table if exists datalake_raw.census_stats_250m_hex_grid;

create external table datalake_raw.census_stats_250m_hex_grid (
  id string,
  geometry string,
  households_ct string,
  inc_bt_2_3_mw_sum string,
  inc_bt_3_5_mw_sum string,
  inc_gt_5_mw_sum string,
  rented_sum string,
  apts_sum string,
  rented_apts_sum string,
  pct_inc_gt_5_mw string,
  city_group string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ','
)
location 's3://5a-datalake/raw/external/census/census_stats_250m_hex_grid/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
