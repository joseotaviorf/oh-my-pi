DROP TABLE staging.dim_facebook_ad;

CREATE TABLE IF NOT EXISTS staging.dim_facebook_ad (
    sk_ad BIGINT,
    ad_id BIGINT,
    ad_name VARCHAR,
    adset_name VARCHAR,
    campaign_name VARCHAR,
    account_name VARCHAR,
    ts_load TIMESTAMP
);