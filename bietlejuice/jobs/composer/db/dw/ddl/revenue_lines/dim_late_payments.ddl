CREATE TABLE IF NOT EXISTS revenue_lines.dim_late_payments
(
	sk_late_payments VARCHAR(255) NOT NULL
	,id_contract BIGINT
	,type_late VARCHAR(255)
	,invoice_theorical_amount NUMERIC(16,3)
	,invoice_paid_amount NUMERIC(38,3)
	,accrual_year_month INTEGER
	,dt_created DATE
	,dt_due DATE
	,dt_paid DATE
	,PRIMARY KEY (sk_late_payments)
)
DISTSTYLE KEY
 DISTKEY (sk_late_payments)
;
ALTER TABLE revenue_lines.dim_late_payments owner to databricks;