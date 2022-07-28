DROP TABLE IF EXISTS customer_support.fact_agent_ranking;
CREATE TABLE IF NOT EXISTS customer_support.fact_agent_ranking (
    sk_agent VARCHAR,
    sk_department VARCHAR,
    sk_group INTEGER,
    sk_date BIGINT,
    agent_age_in_months BIGINT,
    productivity_achievement DOUBLE PRECISION,
    sla_achievement DOUBLE PRECISION,
    csat_achievement DOUBLE PRECISION,
    resolution_achievement DOUBLE PRECISION,
    ra_would_do_business_again_achievement DOUBLE PRECISION,
    ra_score_achievement DOUBLE PRECISION,
    ra_solution_achievement DOUBLE PRECISION,
    multiplication_factor DECIMAL(12,2),
    ranking_score DOUBLE PRECISION,
    ranking_quartile VARCHAR(3),
    ranking_percent_position DOUBLE PRECISION,
    ranking_position INTEGER,
    dt_ranking_week DATE
);
ALTER TABLE customer_support.fact_agent_ranking OWNER TO airflow;