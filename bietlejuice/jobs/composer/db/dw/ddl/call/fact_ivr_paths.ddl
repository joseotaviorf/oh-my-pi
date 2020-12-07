DROP TABLE IF EXISTS call.fact_ivr_paths;
CREATE TABLE IF NOT EXISTS call.fact_ivr_paths (
	sk_call VARCHAR(50),
	step VARCHAR(100),
	answer SMALLINT,
	is_timeout BOOLEAN,
	seconds_elapsed INTEGER,
	ts_answered TIMESTAMP
);
ALTER TABLE call.fact_ivr_paths OWNER TO airflow;