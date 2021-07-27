CREATE SCHEMA IF NOT EXISTS criteo_campaigns;

DROP TABLE IF EXISTS criteo_campaigns.dim_criteo_campaign;
CREATE TABLE IF NOT EXISTS criteo_campaigns.dim_criteo_campaign (
    sk_criteo_campaign VARCHAR PRIMARY KEY,
    id_campaign int,
    advertiser_name VARCHAR,
    campaign_name VARCHAR,
    currency VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE criteo_campaigns.dim_criteo_campaign OWNER TO databricks;

CALL grant_all_permissions_on_schema('criteo_campaigns');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA criteo_campaigns TO GROUP etl;
GRANT ALL ON SCHEMA criteo_campaigns TO GROUP ETL;