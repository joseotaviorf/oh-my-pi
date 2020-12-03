DROP TABLE IF EXISTS sauron.fact_sessions;
CREATE TABLE IF NOT EXISTS sauron.fact_sessions (
	sk_nps_answer BIGINT PRIMARY KEY,
	sk_session BIGINT,
	sk_conversation VARCHAR(100),
	sk_user BIGINT,
	sk_personal_document VARCHAR(50),
	sk_created_date BIGINT,
	is_retained_by_bot BOOLEAN,
	minutes_duration DECIMAL(38,3)
)
ALTER TABLE sauron.fact_sessions OWNER TO airflow;
