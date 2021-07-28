CREATE SCHEMA IF NOT EXISTS mitula;

DROP TABLE IF EXISTS mitula.fact_mitula_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS mitula.fact_mitula_daily_cost_attributions (
    sk_mitula_campaign BIGINT,
    sk_date INTEGER,
    clicks INTEGER,
    desktop_cost FLOAT,
    mobile_cost FLOAT,
    total_cost FLOAT,
    ts_load TIMESTAMP
);
ALTER TABLE mitula.fact_mitula_daily_cost_attributions OWNER TO databricks;

CALL grant_all_permissions_on_schema('mitula');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA mitula TO GROUP etl;
GRANT ALL ON SCHEMA mitula TO GROUP ETL;