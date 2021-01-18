DROP TABLE IF EXISTS call.dim_call;
CREATE TABLE IF NOT EXISTS call.dim_call (
	sk_call VARCHAR(50),
	from_phone_number VARCHAR(50),
	to_phone_number VARCHAR(50),
	direction VARCHAR(50),
	from_city VARCHAR(50),
	from_state VARCHAR(50),
	from_country VARCHAR(50),
	ts_started TIMESTAMP,
	ts_csat_answered TIMESTAMP,
	ts_ended TIMESTAMP,
  	ts_load TIMESTAMP
);
ALTER TABLE call.dim_call OWNER TO airflow;
