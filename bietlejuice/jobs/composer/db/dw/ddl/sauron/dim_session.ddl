DROP TABLE IF EXISTS sauron.dim_session;
CREATE TABLE IF NOT EXISTS sauron.dim_session (
	sk_session BIGINT PRIMARY KEY,
	source VARCHAR(50),
	attendance VARCHAR(20),
	department_name VARCHAR(100),
	customer_phone VARCHAR(25),
	user_type VARCHAR(25),
	flow_step VARCHAR(25),
	status VARCHAR(20),
	ts_created TIMESTAMP,
	ts_first_message TIMESTAMP,
	ts_updated TIMESTAMP,
	ts_load TIMESTAMP
)
ALTER TABLE sauron.dim_session OWNER TO airflow;
