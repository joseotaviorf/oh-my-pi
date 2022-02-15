DROP TABLE IF EXISTS credit.dim_credit_analysis;
CREATE TABLE credit.dim_credit_analysis (
    id_credit_analysis INTEGER,
    id_analyst INTEGER,
    documentation_policy VARCHAR,
    bypass VARCHAR,
    risk_category VARCHAR,
    internal_score INTEGER,
    liquidity VARCHAR,
    reason VARCHAR,
    result VARCHAR,
    level VARCHAR,
    credit_decision_cluster VARCHAR,
    is_manual_analysis BOOLEAN,
    ts_credit_analysis_created TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE credit.dim_credit_analysis OWNER TO airflow;
CALL grant_all_permissions_on_schema('credit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA credit TO GROUP etl;
GRANT ALL ON SCHEMA credit TO GROUP ETL;