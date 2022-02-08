DROP TABLE IF EXISTS customer_support.fact_agent_daily_achievement;
CREATE TABLE IF NOT EXISTS customer_support.fact_agent_daily_achievement (
    sk_achievement VARCHAR,
    sk_agent VARCHAR,
    sk_agent_manager VARCHAR,
    sk_department VARCHAR,
    sk_date BIGINT,
    csat_satisfied_target_achievement FLOAT,
    resolution_rate_target_achievement FLOAT,
    closed_tickets_target_achievement FLOAT,
    avg_days_resolution_target_achievement FLOAT,
    ranking_percent_position FLOAT,
    ranking_10th_percentile_position FLOAT,
    ranking_position INTEGER,
    department_ranking_position INTEGER,
    dt DATE,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.fact_agent_daily_achievement OWNER TO airflow;