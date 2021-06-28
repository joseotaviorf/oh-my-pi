DROP TABLE IF EXISTS customer_support.dim_agent;
CREATE TABLE IF NOT EXISTS customer_support.dim_agent (
    sk_agent VARCHAR,
    email VARCHAR,
    agent_manager VARCHAR,
    full_name VARCHAR,
    agent_company VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.dim_agent OWNER TO airflow;