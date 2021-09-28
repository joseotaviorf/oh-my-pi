DROP TABLE IF EXISTS customer_support.fact_segment;
CREATE TABLE IF NOT EXISTS customer_support.fact_segment (
    sk_ticket BIGINT,
    sk_segment VARCHAR,
    sk_agent VARCHAR,
    sk_department VARCHAR(40),
    sk_channel VARCHAR(40),
    sk_external_service VARCHAR,
    department VARCHAR(100),
    transferred_from_dept VARCHAR(100),
    transferred_to_dept VARCHAR(100),
    transference_type VARCHAR(25),
    transference_reason VARCHAR,
    channel VARCHAR(5),
    is_sla BOOLEAN,
    is_first_segment BOOLEAN,
    is_last_segment BOOLEAN,
    ts_started TIMESTAMP,
    ts_closed TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.fact_segment OWNER TO airflow;