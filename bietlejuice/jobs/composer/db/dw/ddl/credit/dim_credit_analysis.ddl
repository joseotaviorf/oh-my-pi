DROP TABLE IF EXISTS credit.dim_credit_analysis;
CREATE TABLE credit.dim_credit_analysis (
    id_credit_analysis INTEGER,
    id_proposal INTEGER,
    id_analyst INTEGER,
    bypass VARCHAR(255),
    category INTEGER,
    category_within_ca INTEGER,
    category_within_proposal INTEGER,
    documentation_policy VARCHAR(255),
    guarantee_category INTEGER,
    level VARCHAR(255),
    liquidity VARCHAR(255),
    paid_guarantee_type VARCHAR(255),
    standalone_factor VARCHAR(255),
    reason VARCHAR(255),
    risk_category VARCHAR(255),
    internal_score INTEGER,
    max_bypass VARCHAR(255),
    result VARCHAR(255),
    credit_decision_cluster VARCHAR(255),
    is_manual_analysis BOOLEAN,
    is_reprocessed BOOLEAN,
    ts_credit_analysis_created TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE credit.dim_credit_analysis OWNER TO airflow;
CALL grant_all_permissions_on_schema('credit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA credit TO GROUP etl;
GRANT ALL ON SCHEMA credit TO GROUP ETL;