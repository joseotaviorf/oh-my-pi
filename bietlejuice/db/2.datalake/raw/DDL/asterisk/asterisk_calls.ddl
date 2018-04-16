DROP TABLE IF EXISTS datalake_raw.asterisk_calls;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.asterisk_calls (
	waiting_duration STRING,
	agent_extension STRING,
	agent_name STRING,
	id STRING,
	answer_time STRING,
	hangup_time STRING,
	call_start STRING,
	transfer_time STRING,
	queue_name STRING,
	call_state STRING,
	state STRING,
	queue_enter STRING,
	ura_name STRING,
	caller_number STRING,
	connected STRING,
	queue_id STRING,
	name STRING,
	call_duration STRING,
	caller STRING,
	ura_duration STRING,
	context STRING,
	available_agents STRING,
	ura_change STRING,
	ura_code STRING
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://5a-datalake/raw/asterisk/calls/';