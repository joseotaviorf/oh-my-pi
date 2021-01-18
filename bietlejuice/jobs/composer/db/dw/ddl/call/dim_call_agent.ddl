DROP TABLE IF EXISTS call.dim_call_agent;
CREATE TABLE IF NOT EXISTS call.dim_call_agent (
	sk_call_agent VARCHAR(50),
	full_name VARCHAR(100),
	email VARCHAR(100),
	location VARCHAR(25),
	skills VARCHAR(2000),
	ts_created TIMESTAMP,
	ts_updated TIMESTAMP,
  	ts_load TIMESTAMP
);
ALTER TABLE call.dim_call_agent OWNER TO airflow;
