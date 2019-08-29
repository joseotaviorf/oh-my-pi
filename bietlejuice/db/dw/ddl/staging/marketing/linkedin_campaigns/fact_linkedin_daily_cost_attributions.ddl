DROP TABLE staging.fact_linkedin_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS staging.fact_linkedin_daily_cost_attributions (
    sk_campaign VARCHAR(50),
    account_id VARCHAR(50),
    sk_date INTEGER,
    impressions INTEGER,
    clicks INTEGER,
    ctr DOUBLE PRECISION,
    cpc DOUBLE PRECISION,
    ts_load TIMESTAMP
);