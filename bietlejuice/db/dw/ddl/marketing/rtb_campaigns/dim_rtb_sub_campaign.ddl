DROP TABLE IF EXISTS marketing.dim_rtb_sub_campaign;
CREATE TABLE IF NOT EXISTS marketing.dim_rtb_sub_campaign (
    sk_sub_campaign varchar primary key,
    id_campaign varchar,
    campaign_name varchar,
    account_hash varchar,
    account_name varchar,
    account_currency varchar,
    ts_load timestamp
);