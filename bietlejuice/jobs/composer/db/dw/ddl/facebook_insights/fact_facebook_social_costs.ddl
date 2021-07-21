CREATE SCHEMA IF NOT EXISTS facebook_insights;

DROP TABLE IF EXISTS facebook_insights.fact_facebook_social_costs;
CREATE TABLE IF NOT EXISTS facebook_insights.fact_facebook_social_costs (
    sk_ad VARCHAR,
    clicks INTEGER,
    cpc FLOAT,
    cpm FLOAT,
    impressions INTEGER,
    reach INTEGER,
    dt_start DATE,
    dt_stop DATE,
    ts_load TIMESTAMP
);
ALTER TABLE facebook_insights.fact_facebook_social_costs OWNER TO databricks;

CALL grant_all_permissions_on_schema('facebook_insights');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA facebook_insights TO GROUP etl;
GRANT ALL ON SCHEMA facebook_insights TO GROUP ETL;