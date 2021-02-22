DROP TABLE IF EXISTS sauron.fact_session_tags;
CREATE TABLE IF NOT EXISTS sauron.fact_session_tags (
    sk_session BIGINT PRIMARY KEY,
    session_tag VARCHAR(50),
    ts_load TIMESTAMP
)
ALTER TABLE sauron.fact_session_tags OWNER TO airflow;
