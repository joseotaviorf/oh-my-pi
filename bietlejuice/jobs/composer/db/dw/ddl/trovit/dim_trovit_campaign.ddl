CREATE SCHEMA IF NOT EXISTS trovit;

DROP TABLE IF EXISTS trovit.dim_trovit_campaign;
CREATE TABLE IF NOT EXISTS trovit.dim_trovit_campaign (
    sk_trovit_campaign BIGINT,
    campaign_name VARCHAR,
    account_name VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE trovit.dim_trovit_campaign OWNER TO databricks;

CALL grant_all_permissions_on_schema('trovit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA trovit TO GROUP etl;
GRANT ALL ON SCHEMA trovit TO GROUP ETL; 