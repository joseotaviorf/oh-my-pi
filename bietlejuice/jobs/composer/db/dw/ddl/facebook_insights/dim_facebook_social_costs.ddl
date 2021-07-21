CREATE SCHEMA IF NOT EXISTS facebook_insights;

DROP TABLE IF EXISTS facebook_insights.dim_facebook_social_costs;
CREATE TABLE IF NOT EXISTS facebook_insights.dim_facebook_social_costs (
    sk_ad VARCHAR,
    ad_name VARCHAR,
    adset_name VARCHAR,
    campaign_name VARCHAR,
    account_name VARCHAR,
    is_test_campaign BOOLEAN,
    platform_position VARCHAR,
    publisher_platform VARCHAR,
    ts_load TIMESTAMP
)
ALTER TABLE facebook_insights.dim_facebook_social_costs OWNER TO databricks;

CALL grant_all_permissions_on_schema('facebook_insights');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA facebook_insights TO GROUP etl;
GRANT ALL ON SCHEMA facebook_insights TO GROUP ETL;