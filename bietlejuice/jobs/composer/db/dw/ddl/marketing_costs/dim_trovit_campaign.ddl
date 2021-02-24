DROP TABLE IF EXISTS marketing_costs.dim_trovit_campaign;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_trovit_campaign AS (
    sk_trovit_campaign BIGINT,
    campaign_name VARCHAR,
    account_name VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE marketing_costs.dim_trovit_campaign OWNER TO airflow;