CREATE TABLE IF NOT EXISTS marketing_costs.dim_google_ad (
    sk_ad varchar primary key,
    id_ad bigint,
    account_name varchar,
    campaign_name varchar,
    ad_group_name varchar,
    account_descriptive_name varchar,
    ad_type varchar,
    is_test_campaign BOOLEAN,
    ts_load timestamp
);