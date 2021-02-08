DROP TABLE IF EXISTS chattermill.dim_answer_category;
CREATE TABLE IF NOT EXISTS chattermill.dim_answer_category (
    sk_category BIGINT PRIMARY KEY,
    category VARCHAR(20),
    theme VARCHAR(50),
    ts_load TIMESTAMP
);
ALTER TABLE chattermill.dim_answer_category OWNER TO airflow;
