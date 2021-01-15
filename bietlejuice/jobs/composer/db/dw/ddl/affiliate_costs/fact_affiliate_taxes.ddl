DROP TABLE IF EXISTS quintoandar.fact_affiliate_taxes;
CREATE TABLE IF NOT EXISTS quintoandar.fact_affiliate_taxes (
    sk_tax BIGINT,
    sk_payee INTEGER,
    due_amount DECIMAL(20, 2),
    dt_accounting_year_month VARCHAR
    ts_load TIMESTAMP
);
ALTER TABLE quintoandar.fact_affiliate_taxes OWNER TO airflow;