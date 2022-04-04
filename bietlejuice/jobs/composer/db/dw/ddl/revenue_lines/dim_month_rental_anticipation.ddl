CREATE TABLE IF NOT EXISTS revenue_lines.dim_month_rental_anticipation
(
	sk_month_rental_anticipation INTEGER NOT NULL
	,id_contract_ebdb BIGINT
	,nbr_transactions_accepted INTEGER
	,prod_theorical_amount NUMERIC(10,2)
	,prod_theorical_fee NUMERIC(10,2)
	,invoice_theorical_amount NUMERIC(26,3)
	,invoice_theorical_fee NUMERIC(26,3)
	,invoice_paid_amount NUMERIC(38,3)
	,invoice_paid_fee NUMERIC(38,3)
	,accrual_year_month INTEGER
	,dt_created DATE
	,dt_accepted DATE
	,dt_first_accepted DATE
	,dt_due_fee DATE
	,dt_paid_fee DATE
	,PRIMARY KEY (sk_month_rental_anticipation)
)
DISTSTYLE KEY
 DISTKEY (sk_month_rental_anticipation)
;
ALTER TABLE revenue_lines.dim_month_rental_anticipation owner to databricks;