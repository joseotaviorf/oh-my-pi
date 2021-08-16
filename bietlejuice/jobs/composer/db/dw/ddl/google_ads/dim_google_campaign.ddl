CREATE SCHEMA IF NOT EXISTS google_ads;

DROP TABLE IF EXISTS google_ads.dim_google_campaign;
CREATE TABLE IF NOT EXISTS google_ads.dim_google_campaign (
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

ALTER TABLE google_ads.dim_google_campaign OWNER TO databricks;

CALL grant_all_permissions_on_schema('google_ads');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA google_ads TO GROUP etl;
GRANT ALL ON SCHEMA google_ads TO GROUP ETL;