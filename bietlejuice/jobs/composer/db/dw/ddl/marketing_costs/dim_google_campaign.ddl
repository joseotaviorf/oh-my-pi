DROP TABLE IF EXISTS marketing_costs.dim_google_campaign;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_google_campaign(
    sk_campaign VARCHAR PRIMARY KEY,
    id_external_customer BIGINT,
    id_campaign BIGINT,
    campaign_name VARCHAR,
    account_name VARCHAR,
    labels VARCHAR,
    is_test_campaign BOOLEAN,
    report_type VARCHAR,
    ts_load TIMESTAMP
);