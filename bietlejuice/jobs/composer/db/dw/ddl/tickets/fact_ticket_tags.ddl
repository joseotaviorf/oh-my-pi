DROP TABLE IF EXISTS tickets.fact_ticket_tags;
CREATE TABLE IF NOT EXISTS tickets.fact_ticket_tags (
    sk_ticket BIGINT,
    ticket_tag VARCHAR(255),
    ts_updated TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE tickets.fact_ticket_tags OWNER TO airflow;
