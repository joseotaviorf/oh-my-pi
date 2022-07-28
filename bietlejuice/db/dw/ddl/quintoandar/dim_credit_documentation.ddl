DROP TABLE IF EXISTS quintoandar.dim_credit_documentation;
CREATE TABLE quintoandar.dim_credit_documentation (
    sk_proposal BIGINT, 
    sk_credit_evaluation BIGINT, 
    documents_needed VARCHAR, 
    documents_status VARCHAR, 
    ts_credit_started TIMESTAMP,
    ts_credit_updated TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE quintoandar.dim_credit_documentation OWNER TO airflow;
CALL grant_all_permissions_on_schema('quintoandar');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA quintoandar TO GROUP etl;
GRANT ALL ON SCHEMA quintoandar TO GROUP ETL;