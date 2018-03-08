create external table datalake_raw.agents_schedule (
	row_number string,
	agent_user_id string,
	available_date string,
	region_id string,
	region_name string,
	slot_id string,
	slot_start string,
	slot_end string,
	slot_available string,
	slot_status string,
	timestamp string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/ods/agents_schedule/'
tblproperties (
  'skip.header.line.count' = '1'
)
;