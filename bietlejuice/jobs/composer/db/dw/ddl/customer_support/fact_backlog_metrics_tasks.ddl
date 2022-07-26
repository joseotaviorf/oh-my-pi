DROP TABLE IF EXISTS customer_support.fact_backlog_metrics_tasks;
CREATE TABLE IF NOT EXISTS customer_support.fact_backlog_metrics_tasks (
    sk_task VARCHAR(100),
    sk_agent VARCHAR(40),
    sk_taxonomy VARCHAR(40),
    sk_tags VARCHAR(40),
    sk_main_department VARCHAR(40),
    sla_target DOUBLE PRECISION,
    origin VARCHAR(40),
    status VARCHAR(40),
    days_worked BIGINT,
    days_worked_with_days_offs BIGINT,
    days_off BIGINT,
    is_daily_backlog BOOLEAN,
    is_backlog_within_sla BOOLEAN,
    is_backlog_with_exceed_sla BOOLEAN,
    dt_metric_reference DATE,
    ts_started TIMESTAMP,
    ts_solved TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.fact_backlog_metrics_tasks OWNER TO airflow;
