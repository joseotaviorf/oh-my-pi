DROP TABLE IF EXISTS marketing_costs.dim_rtb_campaign;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_rtb_campaign (
    sk_sub_campaign VARCHAR PRIMARY KEY,
    sk_date INTEGER,
    campaign_name VARCHAR,
    account_hash VARCHAR,
    account_name VARCHAR,
    account_currency VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE marketing_costs.dim_rtb_campaign OWNER TO airflow;