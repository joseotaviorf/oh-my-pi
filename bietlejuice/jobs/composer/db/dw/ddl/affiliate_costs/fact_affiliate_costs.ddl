DROP TABLE IF EXISTS quintoandar.fact_affiliate_costs;
CREATE TABLE IF NOT EXISTS quintoandar.fact_affiliate_costs (
    sk_rh_accounting_entry BIGINT,
    sk_date BIGINT,
    sk_user BIGINT,
    cost DECIMAL(20, 2),
    tax DECIMAL(20, 2),
    ts_load TIMESTAMP
);
ALTER TABLE quintoandar.fact_affiliate_costs OWNER TO airflow;