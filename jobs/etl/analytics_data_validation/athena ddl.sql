CREATE EXTERNAL TABLE datalake_raw.amplitude_schema_errors (
app_id string,
event_type string,
event_uuid string,
event_server_upload_time string,
event_platform string,
event_schema string,
validation_time string,
err_path string,
err_validator string,
err_validator_value string,
err_instance string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
   'separatorChar' = ',',
   'quoteChar' = '\"'
   )
STORED AS TEXTFILE
LOCATION 's3://5a-datalake/raw/amplitude/errors/';