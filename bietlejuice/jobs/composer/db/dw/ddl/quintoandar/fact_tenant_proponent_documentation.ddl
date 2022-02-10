DROP TABLE IF EXISTS quintoandar.fact_tenant_proponent_documentation;
CREATE TABLE quintoandar.fact_tenant_proponent_documentation (
    sk_proponent BIGINT,
    sk_proposal BIGINT, 
    sk_first_doc_sent_date BIGINT,
    sk_first_doc_resent_date BIGINT,
    sk_last_doc_resent_date BIGINT,
    amount_docs_needed INTEGER,
    amount_docs_sent INTEGER,
    is_resent BOOLEAN,
    ts_first_doc_sent TIMESTAMP, 
    ts_first_doc_resent TIMESTAMP, 
    ts_last_doc_resent TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE quintoandar.fact_tenant_proponent_documentation OWNER TO airflow;
CALL grant_all_permissions_on_schema('quintoandar');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA quintoandar TO GROUP etl;
GRANT ALL ON SCHEMA quintoandar TO GROUP ETL;