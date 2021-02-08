DROP TABLE IF EXISTS chattermill.fact_answer_category;
CREATE TABLE IF NOT EXISTS chattermill.fact_answer_category (
    sk_answer_category BIGINT PRIMARY KEY,
    sk_answer_classification BIGINT,
    sk_answer INTEGER,
    sk_category INTEGER,
    sk_answer_classification_created_date INTEGER,
    sk_answer_classification_updated_date INTEGER,
    sentiment SMALLINT,
    score SMALLINT,
    original_comment VARCHAR(20000),
    comment VARCHAR(20000),
    ts_load TIMESTAMP
);
ALTER TABLE chattermill.fact_answer_category OWNER TO airflow;
