DROP TABLE IF EXISTS customer_support.fact_agent_daily_productivity;
CREATE TABLE IF NOT EXISTS customer_support.fact_agent_daily_productivity (
    sk_agent VARCHAR,
    sk_department VARCHAR,
    sk_date BIGINT,
    closed_demand BIGINT,
    solved_demand BIGINT,
    tickets_solved_in_time BIGINT,
    tickets_not_solved_in_time BIGINT,
    sum_csat_satisfied_score BIGINT,
    sum_csat_dissatisfied_score BIGINT,
    total_tickets_resolution BIGINT,
    total_tickets_answered_resolution BIGINT,
    total_tickets_with_csat_score BIGINT,
    ra_score_sum BIGINT,
    ra_would_do_business_again BIGINT,
    ra_solved_tickets BIGINT,
    ra_total_tickets_rated BIGINT,
    dt_metric_reference DATE
);
ALTER TABLE customer_support.fact_agent_daily_productivity OWNER TO airflow;