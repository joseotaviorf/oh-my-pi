DROP TABLE IF EXISTS quintoandar.fact_tenant_document_status;
CREATE TABLE quintoandar.fact_tenant_document_status (
    sk_document BIGINT,
    sk_proponent BIGINT,
    sk_proposal BIGINT,
    sk_document_status_date INTEGER,
    document_type VARCHAR,
    status VARCHAR,
    resend_document_reason VARCHAR,
    resend_rank INTEGER,
    days_between_current_and_last_doc_status INTEGER, 
    ts_document_status TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE quintoandar.fact_tenant_document_status OWNER TO airflow;
CALL grant_all_permissions_on_schema('quintoandar');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA quintoandar TO GROUP etl;
GRANT ALL ON SCHEMA quintoandar TO GROUP ETL;