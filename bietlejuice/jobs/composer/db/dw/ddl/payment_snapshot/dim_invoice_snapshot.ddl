CREATE TABLE IF NOT EXISTS payment_snapshot.dim_invoice_snapshot
(
	sk_invoice BIGINT NOT 
	,frequency VARCHAR(50)
	,payment_status VARCHAR(50)
	,"user" VARCHAR(50)
	,due_amount NUMERIC(13,2)
	,paid_amount NUMERIC(13,2)
	,accrual_year_month INTEGER
	,ts_created TIMESTAMP
	,dt_sent DATE
	,dt_due DATE
	,dt_paid DATE
	,ts_snapshot TIMESTAMP
	,PRIMARY KEY (sk_invoice)
);

ALTER TABLE payment_snapshot.dim_invoice_snapshot owner to databricks;