CREATE TABLE IF NOT EXISTS payment_snapshot.dim_invoice_entry_snapshot
(
	sk_invoice_entry BIGINT NOT NULL
	,entry_type VARCHAR(80)
	,from_account_type VARCHAR(50)
	,to_account_type VARCHAR(50)
	,accounting_account VARCHAR(50)
	,producer VARCHAR(255)
	,description VARCHAR(350)
	,invoice_entry_revenue VARCHAR(200)
	,accrual_year_month INTEGER
	,ts_snapshot TIMESTAMP
	,PRIMARY KEY (sk_invoice_entry)
);

ALTER TABLE payment_snapshot.dim_invoice_entry_snapshot owner to databricks;