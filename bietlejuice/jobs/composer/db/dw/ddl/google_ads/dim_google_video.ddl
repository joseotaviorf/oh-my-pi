CREATE SCHEMA IF NOT EXISTS marketing_costs;

DROP TABLE IF EXISTS marketing_costs.dim_google_video;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_google_video (
    sk_video VARCHAR PRIMARY KEY,
    id_video VARCHAR,
    ad_group_name VARCHAR,
    campaign_name VARCHAR,
    device VARCHAR,
    account_name VARCHAR,
    account_descriptive_name VARCHAR,
    report_type VARCHAR,
    is_test_campaign BOOLEAN,
    ts_load TIMESTAMP
);

ALTER TABLE marketing_costs.dim_google_video OWNER TO databricks;

CALL grant_all_permissions_on_schema('marketing_costs');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA marketing_costs TO GROUP etl;
GRANT ALL ON SCHEMA marketing_costs TO GROUP ETL;