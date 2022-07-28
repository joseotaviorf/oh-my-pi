DROP TABLE IF EXISTS customer_support.dim_ticket_tags;
CREATE TABLE IF NOT EXISTS customer_support.dim_ticket_tags (
    sk_tags VARCHAR(40),
    tags VARCHAR(3000)
);
ALTER TABLE customer_support.dim_ticket_tags OWNER TO airflow;
