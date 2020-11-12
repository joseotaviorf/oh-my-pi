DROP TABLE IF EXISTS twilio.dim_call;
CREATE TABLE IF NOT EXISTS twilio.dim_call (
	sk_call VARCHAR(50),
	from_phone_number VARCHAR(20),
	to_phone_number VARCHAR(20),
	direction VARCHAR(20),
	from_city VARCHAR(50),
	from_state VARCHAR(50),
	from_country VARCHAR(50),
	ts_started TIMESTAMP,
	ts_csat_answered TIMESTAMP,
	ts_ended TIMESTAMP
);
ALTER TABLE twilio.dim_call OWNER TO airflow; 
