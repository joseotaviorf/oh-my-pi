CREATE TABLE IF NOT EXISTS revenue_lines.dim_service_fee
(
    sk_service_fee BIGINT
    ,id_contract_ebdb BIGINT
    ,invoice_payment_status VARCHAR(255)
    ,tenant_service_fee NUMERIC(5,3)
    ,prod_theorical_amount DOUBLE PRECISION
    ,invoice_theorical_amount DOUBLE PRECISION
    ,invoice_paid_amount DOUBLE PRECISION
    ,accrual_year_month INTEGER
    ,dt_due DATE
    ,dt_paid DATE
	,PRIMARY KEY (sk_service_fee)
)
DISTSTYLE KEY
 DISTKEY (sk_service_fee)
;
ALTER TABLE revenue_lines.dim_service_fee owner to databricks;