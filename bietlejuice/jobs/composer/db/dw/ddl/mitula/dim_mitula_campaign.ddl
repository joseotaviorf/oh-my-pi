CREATE SCHEMA IF NOT EXISTS mitula;

DROP TABLE IF EXISTS mitula.dim_mitula_campaign;
CREATE TABLE IF NOT EXISTS mitula.dim_mitula_campaign (
    sk_mitula_campaign BIGINT,
    campaign_name VARCHAR,
    account_name VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE mitula.dim_mitula_campaign OWNER TO databricks;

CALL grant_all_permissions_on_schema('mitula');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA mitula TO GROUP etl;
GRANT ALL ON SCHEMA mitula TO GROUP ETL;