DROP TABLE marketing.dim_facebook_ad;

CREATE TABLE IF NOT EXISTS marketing.dim_facebook_ad (
    sk_ad BIGINT,
    ad_id BIGINT,
    ad_name VARCHAR,
    adset_name VARCHAR,
    campaign_name VARCHAR,
    account_name VARCHAR,
    ts_load TIMESTAMP
);