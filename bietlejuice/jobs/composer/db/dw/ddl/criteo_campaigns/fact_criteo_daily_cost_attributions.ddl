CREATE SCHEMA IF NOT EXISTS criteo_campaigns;

DROP TABLE IF EXISTS criteo_campaigns.fact_criteo_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS criteo_campaigns.fact_criteo_daily_cost_attributions (
    sk_criteo_campaign VARCHAR PRIMARY KEY,
    sk_date INTEGER,
    clicks INTEGER,
    impressions INTEGER,
    audience VARCHAR,
    cost DOUBLE PRECISION,
    all_sales VARCHAR,
    revenue DOUBLE PRECISION,
    composition_win DOUBLE PRECISION,
    cost_per_click DOUBLE PRECISION,
    ts_load TIMESTAMP
);
ALTER TABLE criteo_campaigns.fact_criteo_daily_cost_attributions OWNER TO databricks;

CALL grant_all_permissions_on_schema('criteo_campaigns');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA criteo_campaigns TO GROUP etl;
GRANT ALL ON SCHEMA criteo_campaigns TO GROUP ETL;