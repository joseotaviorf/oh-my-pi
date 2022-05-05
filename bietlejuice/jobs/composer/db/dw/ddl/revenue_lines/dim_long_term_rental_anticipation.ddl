CREATE TABLE IF NOT EXISTS revenue_lines.dim_long_term_rental_anticipation
(
	sk_long_term_rental_anticipation INTEGER NOT NULL
	,id_contract_ebdb BIGINT
	,months_anticipated BIGINT
	,installment BIGINT
	,total_installments BIGINT
	,total_rent NUMERIC(10,2)
	,nbr_transactions_signed INTEGER
	,prod_theorical_amount NUMERIC(11,2)
	,prod_theorical_fee NUMERIC(10,2)
	,invoice_theorical_amount NUMERIC(26,3)
	,invoice_paid_amount NUMERIC(38,3)
	,accrual_year_month VARCHAR(255)
	,dt_due DATE
	,dt_paid DATE
	,dt_created DATE
	,dt_signed DATE
	,ts_load TIMESTAMP
	,PRIMARY KEY (sk_long_term_rental_anticipation)
)
DISTSTYLE KEY
 DISTKEY (sk_long_term_rental_anticipation)
;
ALTER TABLE revenue_lines.dim_long_term_rental_anticipation owner to databricks;