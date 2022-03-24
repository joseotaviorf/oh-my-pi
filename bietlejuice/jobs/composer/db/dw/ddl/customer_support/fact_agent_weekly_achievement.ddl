DROP TABLE IF EXISTS customer_support.fact_agent_weekly_achievement;
CREATE TABLE IF NOT EXISTS customer_support.fact_agent_weekly_achievement (
    sk_achievement VARCHAR,
    sk_agent VARCHAR,
    sk_department VARCHAR,
    achievement_weighted_score FLOAT,
    ranking_quartile VARCHAR,
    ranking_percent_position FLOAT,
    ranking_position INTEGER,
    closed_tickets_target_achievement FLOAT,
    csat_satisfied_target_achievement FLOAT,
    resolution_rate_target_achievement FLOAT,
    avg_days_resolution_target_achievement FLOAT,
    dt_week_started DATE,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.fact_agent_weekly_achievement OWNER TO airflow;