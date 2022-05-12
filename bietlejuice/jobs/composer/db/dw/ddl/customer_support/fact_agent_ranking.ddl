DROP TABLE IF EXISTS customer_support.fact_agent_ranking;
CREATE TABLE IF NOT EXISTS customer_support.fact_agent_ranking (
    sk_agent VARCHAR,
    sk_department VARCHAR,
    sk_group INTEGER,
    multiplication_factor DOUBLE PRECISION,
    ranking_score DOUBLE PRECISION,
    ranking_quartile VARCHAR(3),
    ranking_percent_position DOUBLE PRECISION,
    ranking_position INTEGER,
    dt_ranking_week DATE
);
ALTER TABLE customer_support.fact_agent_ranking OWNER TO airflow;