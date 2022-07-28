DROP TABLE IF EXISTS credit.dim_guarantee_policy;
CREATE TABLE credit.dim_guarantee_policy (
    id_guarantee_category INTEGER,
    id_risk_category INTEGER,
    guarantee_factor DECIMAL(6,2),
    deposit_factor DECIMAL(6,2),
    category_description VARCHAR,
    is_guarantee_allowed BOOLEAN,
    is_deposit_allowed BOOLEAN,
    ts_guarantee_category_created TIMESTAMP,
    ts_guarantee_category_updated TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE credit.dim_guarantee_policy OWNER TO airflow;
CALL grant_all_permissions_on_schema('credit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA credit TO GROUP etl;
GRANT ALL ON SCHEMA credit TO GROUP ETL;