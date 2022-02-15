DROP TABLE IF EXISTS credit.dim_variant;
CREATE TABLE credit.dim_variant (
    id_variant INTEGER,
    id_experiment INTEGER,
    variant_name VARCHAR,
    variant_description VARCHAR,
    variant_percentage_paticipation_on_test FLOAT,
    ts_load TIMESTAMP
);

ALTER TABLE credit.dim_variant OWNER TO airflow;
CALL grant_all_permissions_on_schema('credit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA credit TO GROUP etl;
GRANT ALL ON SCHEMA credit TO GROUP ETL;