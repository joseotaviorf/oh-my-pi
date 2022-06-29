DROP TABLE IF EXISTS debt_recovery.fact_negotiation;
CREATE TABLE IF NOT EXISTS debt_recovery.fact_negotiation (
    id_negotiation VARCHAR,
    id_contract VARCHAR,
    status VARCHAR,
    qt_installments BIGINT,
    qt_installments_paid BIGINT,
    total_expected_amout DECIMAL(22,2),
    paid_amount DECIMAL(22,2),
    negotiation_original_amount DECIMAL(22,2),
    negotiation_discount_amount DECIMAL(22,2),
    negotiation_fees_amount DECIMAL(23,2),
    breached_installment INT,
    is_contract_recurrent_debtor BOOLEAN,
    has_renegotiated BOOLEAN,
    dt_expected_end DATE,
    ts_paid_all TIMESTAMP,
    ts_breach TIMESTAMP,
    ts_created_at TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE debt_recovery.fact_negotiation OWNER TO databricks;
