drop table if exists datalake_clean.ods_fact_house_status;
create external table datalake_clean.ods_fact_house_status (
	sk_house string,
	sk_region string,
	status_history string,
	sk_min_version_status_date string,
	sk_min_status_date string,
	sk_max_status_date string,
	dt_timestamp string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/house_status'
tblproperties (
  'skip.header.line.count' = '1'
)
;