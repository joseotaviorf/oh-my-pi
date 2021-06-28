DROP TABLE IF EXISTS customer_support.fact_task;
CREATE TABLE IF NOT EXISTS customer_support.fact_task (
    sk_ticket BIGINT,
    sk_task VARCHAR,
    sk_agent VARCHAR,
    sk_department VARCHAR(40),
    sk_channel VARCHAR(40),
    sk_segment VARCHAR,
    department VARCHAR(100),
    transferred_from_dept VARCHAR(100),
    transferred_to_dept VARCHAR(100),
    transference_type VARCHAR(25),
    channel VARCHAR(5),
    is_sla BOOLEAN,
    is_first_task BOOLEAN,
    is_last_task BOOLEAN,
    ts_started TIMESTAMP,
    ts_closed TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.fact_task OWNER TO airflow;