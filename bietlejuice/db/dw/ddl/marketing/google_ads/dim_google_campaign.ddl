CREATE TABLE IF NOT EXISTS marketing.dim_google_campaign (
    sk_campaign bigint,
    account_id varchar,
    campaign_id varchar,
    campaign_name varchar,
    account_name varchar,
    labels varchar,
    ts_load TIMESTAMP
)