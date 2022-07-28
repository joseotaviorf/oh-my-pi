DROP TABLE IF EXISTS customer_support.fact_demand_metrics_tasks;
CREATE TABLE IF NOT EXISTS customer_support.fact_demand_metrics_tasks (
    sk_task VARCHAR(100),
    sk_agent VARCHAR(40),
    sk_taxonomy VARCHAR(40),
    sk_tags VARCHAR(40),
    sk_main_department VARCHAR(40),
    sla_target DOUBLE PRECISION,
    origin VARCHAR(40),
    status VARCHAR(40),
    time_spent_solved_within_sla BIGINT,
    time_spent_solved_with_exceed_sla BIGINT,
    days_worked BIGINT,
    days_off BIGINT,
    is_ticket_solved_within_sla BOOLEAN,
    is_ticket_solved_with_exceed_sla BOOLEAN,
    is_received_demand BOOLEAN,
    is_solved_demand BOOLEAN,
    is_closed_demand BOOLEAN,
    ts_started TIMESTAMP,
    ts_solved TIMESTAMP,
    ts_closed TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.fact_demand_metrics_tasks OWNER TO airflow;
