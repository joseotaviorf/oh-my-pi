DROP TABLE IF EXISTS twilio.dim_call_agent;
CREATE TABLE IF NOT EXISTS twilio.dim_call_agent (
	sk_call_agent VARCHAR(50),
	full_name VARCHAR(100),
	email VARCHAR(100),
	location VARCHAR(25),
	skills VARCHAR(2000),
	ts_created TIMESTAMP,
	ts_updated TIMESTAMP
);
ALTER TABLE twilio.dim_call_agent OWNER TO airflow;