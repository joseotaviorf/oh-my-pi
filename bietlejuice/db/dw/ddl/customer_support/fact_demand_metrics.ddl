DROP TABLE IF EXISTS customer_support.fact_demand_metrics;
CREATE TABLE IF NOT EXISTS customer_support.fact_demand_metrics (
    sk_agent VARCHAR,
    sk_demand_type VARCHAR,
    sk_metric_reference_date BIGINT,
    demand_type  VARCHAR(100),
    received_demand BIGINT,
    solved_demand BIGINT,
    tickets_solved_within_sla BIGINT,
    tickets_solved_with_exceed_sla BIGINT,
    days_spent_on_solved_tickets_within_sla BIGINT,
    days_spent_on_solved_tickets_with_exceed_sla BIGINT,
    total_days_spent BIGINT,
    daily_backlog BIGINT,
    backlog_within_sla BIGINT,
    backlog_with_exceed_sla BIGINT,
    is_sunday BOOLEAN,
    dt_metric_reference DATE,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.fact_demand_metrics OWNER TO airflow;