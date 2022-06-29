DROP TABLE IF EXISTS debt_recovery.fact_installment;
CREATE TABLE IF NOT EXISTS debt_recovery.fact_installment (
    id_installment VARCHAR,
    id_negotiation VARCHAR,
    total_amount DECIMAL(12,2),
    status VARCHAR,
    purpose VARCHAR,
    payment_type VARCHAR,
    days_paid_late INT,
    dt_due DATE,
    ts_paid TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE debt_recovery.fact_installment OWNER TO databricks;
