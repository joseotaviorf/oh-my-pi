DROP TABLE IF EXISTS marketing_costs.dim_facebook_social_costs;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_facebook_social_costs (
    sk_ad VARCHAR,
    ad_name VARCHAR,
    adset_name VARCHAR,
    campaign_name VARCHAR,
    account_name VARCHAR,
    is_test_campaign BOOLEAN,
    platform_position VARCHAR,
    publisher_platform VARCHAR,
    ts_load TIMESTAMP
)
ALTER TABLE marketing_costs.dim_facebook_social_costs OWNER TO airflow;