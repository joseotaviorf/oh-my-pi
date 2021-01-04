DROP TABLE IF EXISTS marketing_costs.dim_facebook_ad;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_facebook_ad (
    sk_ad VARCHAR,
    ad_name VARCHAR,
    adset_name VARCHAR,
    campaign_name VARCHAR,
    account_name VARCHAR,
    is_test_campaign BOOLEAN,
    ts_load TIMESTAMP
);