DROP TABLE IF EXISTS customer_support.dim_channel;
CREATE TABLE IF NOT EXISTS customer_support.dim_channel (
    sk_channel VARCHAR(40),
    channel VARCHAR(5),
    direction VARCHAR(10),
    tags VARCHAR(2800),
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.dim_channel OWNER TO airflow;