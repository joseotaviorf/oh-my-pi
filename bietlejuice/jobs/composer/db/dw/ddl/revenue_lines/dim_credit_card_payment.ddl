CREATE TABLE IF NOT EXISTS revenue_lines.dim_credit_card_payment
(
	sk_credit_card_payment BIGINT NOT NULL
	,id_contract_ebdb BIGINT
	,status VARCHAR(255)
	,brand_name VARCHAR(255)
	,type_paid VARCHAR(255)
	,installments INTEGER
	,invoice_theorical_amount NUMERIC(13,2)
	,invoice_paid_amount NUMERIC(13,2)
	,invoice_paid_fee NUMERIC(14,2)
	,accrual_year_month INTEGER
	,dt_ccp_created DATE
	,dt_due DATE
	,dt_paid DATE
	,ts_load TIMESTAMP
	,PRIMARY KEY (sk_credit_card_payment)
)
DISTSTYLE KEY
 DISTKEY (sk_credit_card_payment)
;
ALTER TABLE revenue_lines.dim_credit_card_payment owner to databricks;