drop table if exists datalake_raw.taxonomy_supply;

create external table datalake_raw.taxonomy_supply (
  lead_type string,
  lead_origin string,
  lead_utm_medium string,
  lead_utm_source string,
  is_branded string,
  is_doorman string,
  is_sales_direct_register string,
  is_cx_direct_register string,
  has_isales_intervention string,
  is_b2b string,
  is_call_center string,
  mkt_category string,
  mkt_flow string,
  mkt_completion string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string,
  mkt_platform string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/files/taxonomy_supply/'
tblproperties (
  'skip.header.line.count' = '1'
)
;