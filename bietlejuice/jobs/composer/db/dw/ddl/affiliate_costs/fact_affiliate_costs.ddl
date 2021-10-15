CREATE SCHEMA IF NOT EXISTS quintoandar;

DROP TABLE IF EXISTS quintoandar.fact_affiliate_costs;
CREATE TABLE IF NOT EXISTS quintoandar.fact_affiliate_costs (
    sk_rh_accounting_entry BIGINT,
    sk_payee BIGINT,
    sk_date BIGINT,
    sk_user BIGINT,
    cost DECIMAL(20, 2),
    ts_load TIMESTAMP
);
ALTER TABLE quintoandar.fact_affiliate_costs OWNER TO databricks;

CALL grant_all_permissions_on_schema('quintoandar');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA quintoandar TO GROUP etl;
GRANT ALL ON SCHEMA quintoandar TO GROUP ETL;