DROP TABLE IF EXISTS marketing_costs.dim_criteo_campaign;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_criteo_campaign (
    sk_criteo_campaign varchar primary key,
    id_campaign int,
    advertiser_name varchar,
    campaign_name varchar,
    currency varchar,
    ts_load timestamp
);