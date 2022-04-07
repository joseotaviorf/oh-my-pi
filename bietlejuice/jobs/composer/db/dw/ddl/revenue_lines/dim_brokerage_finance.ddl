CREATE TABLE IF NOT EXISTS revenue_lines.dim_brokerage_finance
(
	sk_brokerage_finance BIGINT NOT NUL
	,id_contract_ebdb BIGINT
	,prod_theorical_amount DOUBLE PRECISION
	,prod_theorical_fee DOUBLE PRECISION
	,invoice_theorical_amount NUMERIC(26,3)
	,invoice_paid_amount NUMERIC(38,3)
	,invoice_theorical_fee NUMERIC(26,3)
	,invoice_paid_fee NUMERIC(38,3)
	,installment DOUBLE PRECISION
	,total_installments INTEGER
	,premium_fee DOUBLE PRECISION
	,real_state_agent_share DOUBLE PRECISION
	,accrual_year_month INTEGER
	,dt_bf_created DATE
	,dt_due_fee DATE
	,dt_paid_fee DATE
	,ts_load TIMESTAMP
	,PRIMARY KEY (sk_brokerage_finance)
)
DISTSTYLE KEY
 DISTKEY (sk_brokerage_finance)
;
ALTER TABLE revenue_lines.dim_brokerage_finance owner to databricks;