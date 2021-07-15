DROP TABLE IF EXISTS customer_support.fact_csat;
CREATE TABLE IF NOT EXISTS customer_support.fact_csat (
    sk_ticket BIGINT,
    channel VARCHAR(10),
    csat_comment VARCHAR(1000),
    is_solved BOOLEAN,
    csat_score INTEGER,
    ts_survey TIMESTAMP,
    ts_response TIMESTAMP
);
ALTER TABLE customer_support.fact_csat OWNER TO airflow;
