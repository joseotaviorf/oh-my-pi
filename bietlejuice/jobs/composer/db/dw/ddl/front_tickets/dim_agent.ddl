DROP TABLE IF EXISTS front_tickets.dim_agent;
CREATE TABLE IF NOT EXISTS front_tickets.dim_agent (
    sk_agent VARCHAR,
    email VARCHAR,
    agent_manager VARCHAR,
    full_name VARCHAR,
    agent_company VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE front_tickets.dim_agent OWNER TO airflow;