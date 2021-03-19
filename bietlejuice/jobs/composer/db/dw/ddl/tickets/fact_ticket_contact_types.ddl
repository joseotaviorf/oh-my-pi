DROP TABLE IF EXISTS tickets.fact_ticket_contact_types;
CREATE TABLE IF NOT EXISTS tickets.fact_ticket_contact_types (
    sk_ticket BIGINT,
    sk_updated INT,
    contact_type_tag VARCHAR(75),
    client_taxonomy VARCHAR(5),
    category_taxonomy VARCHAR(5),
    is_contact_type_taxonomy BOOLEAN,
    ts_updated TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE tickets.fact_ticket_contact_types OWNER TO airflow;
