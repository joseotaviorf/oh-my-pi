DROP TABLE IF EXISTS marketing_costs.fact_facebook_social_costs;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_facebook_social_costs (
    sk_ad VARCHAR,
    clicks INTEGER,
    cpc FLOAT,
    cpm FLOAT,
    impressions INTEGER,
    reach INTEGER,
    dt_start DATE,
    dt_stop DATE,
    ts_load TIMESTAMP
);
ALTER TABLE marketing_costs.fact_facebook_social_costs OWNER TO airflow;