DROP TABLE IF EXISTS customer_support.dim_ranking_targets;
CREATE TABLE IF NOT EXISTS customer_support.dim_ranking_targets (
    sk_group INTEGER,
    sk_team VARCHAR,
    sk_team_leader VARCHAR,
    team VARCHAR,
    team_leader VARCHAR,
    company VARCHAR,
    target_resolution FLOAT,
    target_csat FLOAT,
    target_frt FLOAT,
    target_productivity INTEGER,
    target_reclameaqui_would_back_make_business FLOAT,
    dt_start DATE,
    dt_end DATE,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.dim_ranking_targets OWNER TO airflow;