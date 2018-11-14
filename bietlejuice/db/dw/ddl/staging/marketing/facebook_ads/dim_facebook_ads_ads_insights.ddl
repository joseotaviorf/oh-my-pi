CREATE TABLE IF NOT EXISTS staging.dim_facebook_ads_ads_insights (
    sk_ad BIGINT,
    ad_id BIGINT,
    ad_name VARCHAR,
    adset_name VARCHAR,
    campaign_name VARCHAR,
    account_name VARCHAR,
    ts_load TIMESTAMP
);