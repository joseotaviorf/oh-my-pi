CREATE SCHEMA IF NOT EXISTS marketing_costs;

DROP TABLE IF EXISTS marketing_costs.dim_google_campaign;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_google_campaign (
    sk_campaign VARCHAR PRIMARY KEY,
    id_external_customer BIGINT,
    id_campaign BIGINT,
    campaign_name VARCHAR,
    labels VARCHAR,
    account_name VARCHAR,
    account_descriptive_name VARCHAR,
    report_type VARCHAR,
    is_test_campaign BOOLEAN,
    ts_load TIMESTAMP
);

ALTER TABLE marketing_costs.dim_google_campaign OWNER TO databricks;

CALL grant_all_permissions_on_schema('marketing_costs');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA marketing_costs TO GROUP etl;
GRANT ALL ON SCHEMA marketing_costs TO GROUP ETL;