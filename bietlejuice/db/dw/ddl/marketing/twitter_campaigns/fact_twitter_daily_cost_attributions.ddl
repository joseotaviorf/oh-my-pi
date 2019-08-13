DROP TABLE marketing.fact_twitter_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS marketing.fact_twitter_daily_cost_attributions (
    sk_ad VARCHAR(50),
    id_ad VARCHAR(50),
    sk_ad_group VARCHAR(50),
    sk_campaign VARCHAR(50),
    account_id VARCHAR(50),
    sk_date INTEGER,
    mobile_impressions INTEGER,
    desktop_impressions INTEGER,
    other_impressions INTEGER,
    total_impressions INTEGER,
    mobile_cost DOUBLE PRECISION,
    desktop_cost DOUBLE PRECISION,
    other_cost DOUBLE PRECISION,
    total_cost DOUBLE PRECISION,
    ts_load TIMESTAMP
);