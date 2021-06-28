DROP TABLE IF EXISTS customer_support.dim_taxonomy;
CREATE TABLE IF NOT EXISTS customer_support.dim_taxonomy (
    sk_taxonomy VARCHAR(40),
    customer_type VARCHAR,
    customer_type_tag VARCHAR,
    request_type VARCHAR,
    motivation VARCHAR,
    theme VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.dim_taxonomy OWNER TO airflow;