DROP TABLE IF EXISTS credit.dim_experiment;
CREATE TABLE credit.dim_experiment (
    id_experiment INTEGER,
    experiment_name VARCHAR,
    experiment_description VARCHAR,
    is_experiment_running BOOLEAN,
    has_experiment_ran_last_month BOOLEAN,
    has_experiment_ran_last_3_months BOOLEAN,
    has_experiment_ran_last_6_months BOOLEAN,
    has_experiment_ran_last_year BOOLEAN,
    ts_experiment_started TIMESTAMP,
    ts_experiment_ended TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE credit.dim_experiment OWNER TO airflow;
CALL grant_all_permissions_on_schema('credit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA credit TO GROUP etl;
GRANT ALL ON SCHEMA credit TO GROUP ETL;