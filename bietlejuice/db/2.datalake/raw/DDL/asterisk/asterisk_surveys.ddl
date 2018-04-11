DROP TABLE IF EXISTS datalake_raw.asterisk_surveys;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.asterisk_surveys (
	agent_name STRING,
	client_number STRING,
	queue_number STRING,
	`timestamp` STRING,
	agent_number STRING,
	question1 INT,
	question2 INT,
	unique_id STRING
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://5a-datalake/raw/asterisk/survey/';