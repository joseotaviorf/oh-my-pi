DROP TABLE IF EXISTS front_tickets.dim_taxonomy;
CREATE TABLE IF NOT EXISTS front_tickets.dim_taxonomy (
    sk_taxonomy VARCHAR(40),
    customer_type VARCHAR,
    customer_type_tag VARCHAR,
    request_type VARCHAR,
    motivation VARCHAR,
    theme VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE front_tickets.dim_taxonomy OWNER TO airflow;