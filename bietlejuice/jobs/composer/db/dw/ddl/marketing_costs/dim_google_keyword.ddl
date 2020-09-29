DROP TABLE IF EXISTS marketing_costs.dim_google_keyword;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_google_keyword(
    sk_keyword VARCHAR PRIMARY KEY,
    id_keyword BIGINT,
    keyword_name VARCHAR,
    account_name VARCHAR,
    campaign_name VARCHAR,
    ad_group_name VARCHAR,
    match_type VARCHAR,
    is_test_campaign BOOLEAN,
    report_type VARCHAR,
    ts_load TIMESTAMP
);