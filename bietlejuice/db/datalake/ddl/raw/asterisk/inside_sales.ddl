drop table datalake_raw.inside_sales;

create external table datalake_raw.inside_sales (
	rep_name string,
	rep_id string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/asterisk/inside_sales/'
;