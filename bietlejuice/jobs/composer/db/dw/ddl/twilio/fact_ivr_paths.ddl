DROP TABLE IF EXISTS twilio.fact_ivr_paths;
CREATE TABLE IF NOT EXISTS twilio.fact_ivr_paths (
	sk_call VARCHAR(50),
	step VARCHAR(100),
	answer TINYINT,
	is_timeout BOOLEAN,
	seconds_elapsed INTEGER,
	ts_answered TIMESTAMP
);
ALTER TABLE twilio.fact_ivr_paths OWNER TO airflow;