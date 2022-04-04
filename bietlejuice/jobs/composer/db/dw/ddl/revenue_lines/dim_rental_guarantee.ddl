CREATE TABLE IF NOT EXISTS revenue_lines.dim_rental_guarantee
(
	sk_rental_guarantee INTEGER NOT NULL
	,id_contract_ebdb INTEGER
	,id_charge INTEGER
	,guarantee_status VARCHAR(255)
	,charge_status VARCHAR(255)
	,charge_type VARCHAR(255)
	,total_installments INTEGER
	,installment_number DOUBLE PRECISION
	,monthly_revenue DOUBLE PRECISION
	,accrual_year_month DATE
	,ts_guarantee_created TIMESTAMP
	,ts_charge_created TIMESTAMP
	,ts_guarantee_paid TIMESTAMP
	,PRIMARY KEY (sk_rental_guarantee)
)
DISTSTYLE KEY
 DISTKEY (sk_rental_guarantee)
;
ALTER TABLE revenue_lines.dim_rental_guarantee owner to databricks;