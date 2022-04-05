DROP TABLE IF EXISTS credit.fact_proposal_credit_flows;
CREATE TABLE credit.fact_proposal_credit_flows (
    sk_proposal INTEGER,
    sk_credit_analysis INTEGER,
    sk_client BIGINT,
    sk_first_credit_analysis INTEGER,
    sk_first_variant INTEGER,
    sk_guarantee_category INTEGER,
    sk_last_credit_analysis INTEGER,
    sk_offer INTEGER,
    sk_region BIGINT,
    sk_offer_submitted_date BIGINT,
    sk_offer_approved_date BIGINT,
    sk_last_credit_evaluation_init BIGINT,
    sk_last_credit_evaluation_positive BIGINT,
    sk_last_credit_evaluation_negative BIGINT,
    sk_credit_evaluation_approved_date BIGINT,
    sk_tenant_first_doc_sent_date BIGINT,
    sk_tenant_doc_complete_date BIGINT,
    sk_credit_analysis_approved_date BIGINT,
    sk_guarantee_paid_date BIGINT,
    funnel_step VARCHAR(255),
    is_first_credit_evaluation BOOLEAN,
    is_last_credit_evaluation BOOLEAN,
    ts_load TIMESTAMP
);

ALTER TABLE credit.fact_proposal_credit_flows OWNER TO airflow;
CALL grant_all_permissions_on_schema('credit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA credit TO GROUP etl;
GRANT ALL ON SCHEMA credit TO GROUP ETL;