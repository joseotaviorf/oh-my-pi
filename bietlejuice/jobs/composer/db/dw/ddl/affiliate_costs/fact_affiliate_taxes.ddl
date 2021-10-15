CREATE SCHEMA IF NOT EXISTS quintoandar;

DROP TABLE IF EXISTS quintoandar.fact_affiliate_taxes;
CREATE TABLE IF NOT EXISTS quintoandar.fact_affiliate_taxes (
    sk_tax BIGINT,
    sk_payee BIGINT,
    due_amount DECIMAL(20, 2),
    dt_accounting_year_month VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE quintoandar.fact_affiliate_taxes OWNER TO databricks;

CALL grant_all_permissions_on_schema('quintoandar');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA quintoandar TO GROUP etl;
GRANT ALL ON SCHEMA quintoandar TO GROUP ETL;