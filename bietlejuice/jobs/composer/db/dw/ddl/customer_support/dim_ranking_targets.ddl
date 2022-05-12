DROP TABLE IF EXISTS customer_support.dim_ranking_targets;
CREATE TABLE IF NOT EXISTS customer_support.dim_ranking_targets (
    sk_group INTEGER,
    sk_department VARCHAR,
    department VARCHAR,
    target_resolution FLOAT,
    target_csat FLOAT,
    target_sla FLOAT,
    target_productivity INTEGER,
    target_ra_score INTEGER,
    target_ra_solution_rate FLOAT,
    target_ra_would_do_business_again FLOAT,
    dt_start DATE,
    dt_end DATE,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.dim_ranking_targets OWNER TO airflow;