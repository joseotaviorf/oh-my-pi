DROP TABLE IF EXISTS marketing_costs.dim_mitula_campaign;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_mitula_campaign AS (
    sk_mitula_campaign BIGINT,
    campaign_name VARCHAR,
    account_name VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE marketing_costs.dim_mitula_campaign OWNER TO airflow;