DROP TABLE IF EXISTS customer_support.fact_agent_daily_productivity;
CREATE TABLE IF NOT EXISTS customer_support.fact_agent_daily_productivity (
    sk_agent VARCHAR,
    sk_agent_manager VARCHAR,
    sk_department VARCHAR,
    sk_date BIGINT,
    total_csat_satisfied_score BIGINT,
    total_csat_dissatisfied_score BIGINT,
    total_tickets_with_csat_score BIGINT,
    total_tickets_resolution BIGINT,
    total_tickets_answered_resolution BIGINT,
    total_tickets BIGINT,
    total_tickets_with_taxonomy BIGINT,
    total_minutes_resolution_time BIGINT,
    avg_days_resolution_time FLOAT,
    total_crm_tasks_solved BIGINT,
    agent_age_in_months INTEGER,
    dt DATE,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.fact_agent_daily_productivity OWNER TO airflow;