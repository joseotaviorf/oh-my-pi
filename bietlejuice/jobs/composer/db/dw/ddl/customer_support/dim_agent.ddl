DROP TABLE IF EXISTS customer_support.dim_agent;
CREATE TABLE IF NOT EXISTS customer_support.dim_agent (
    sk_agent VARCHAR,
    email VARCHAR,
    agent_manager VARCHAR,
    full_name VARCHAR,
    agent_company VARCHAR,
    dt_agent_start DATE,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.dim_agent OWNER TO airflow;