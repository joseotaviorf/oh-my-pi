DROP TABLE IF EXISTS customer_support.fact_csat;
CREATE TABLE IF NOT EXISTS customer_support.fact_csat (
    sk_ticket BIGINT,
    channel VARCHAR(10),
    csat_comment VARCHAR(2000),
    source VARCHAR(10),
    resolution_survey BOOLEAN,
    csat_score INTEGER,
    ts_survey TIMESTAMP,
    ts_response TIMESTAMP
);
ALTER TABLE customer_support.fact_csat OWNER TO airflow;
