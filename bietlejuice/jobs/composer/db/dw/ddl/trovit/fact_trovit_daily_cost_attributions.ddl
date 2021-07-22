CREATE SCHEMA IF NOT EXISTS trovit;

DROP TABLE IF EXISTS trovit.fact_trovit_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS trovit.fact_trovit_daily_cost_attributions (
    sk_trovit_campaign BIGINT,
    sk_date INTEGER,
    clicks INTEGER,
    desktop_cost FLOAT,
    mobile_cost FLOAT,
    total_cost FLOAT,
    ts_load TIMESTAMP
);
ALTER TABLE trovit.fact_trovit_daily_cost_attributions OWNER TO databricks;

CALL grant_all_permissions_on_schema('trovit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA trovit TO GROUP etl;
GRANT ALL ON SCHEMA trovit TO GROUP ETL; 