CREATE SCHEMA IF NOT EXISTS quintoandar;

DROP TABLE IF EXISTS quintoandar.dim_affiliate_cost;
CREATE TABLE IF NOT EXISTS quintoandar.dim_affiliate_cost (
    sk_rh_accounting_entry BIGINT,
    sk_payee BIGINT,
    city_group VARCHAR(255),
    description VARCHAR(255),
    source_bill_item VARCHAR(255),
    commission_type VARCHAR(255),
    cost_center_code VARCHAR(255),
    mkt_origin VARCHAR(255),
    ts_load TIMESTAMP
);
ALTER TABLE quintoandar.dim_affiliate_cost OWNER TO databricks;

CALL grant_all_permissions_on_schema('quintoandar');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA quintoandar TO GROUP etl;
GRANT ALL ON SCHEMA quintoandar TO GROUP ETL;