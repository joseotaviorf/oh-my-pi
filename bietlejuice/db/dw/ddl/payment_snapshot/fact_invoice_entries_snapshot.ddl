CREATE TABLE IF NOT EXISTS payment_snapshot.fact_invoice_entries_snapshot
(
	sk_invoice_entry BIGINT NOT NULL
	,sk_invoice BIGINT
	,sk_contract BIGINT
	,sk_contract_user BIGINT
	,sk_region BIGINT
	,sk_created_date INTEGER
	,sk_due_date INTEGER
	,sk_paid_date INTEGER
	,brl_entry_due_amount NUMERIC(16,3)
	,brl_entry_paid_amount NUMERIC(38,2)
	,ts_created TIMESTAMP
	,ts_snapshot TIMESTAMP
	,PRIMARY KEY (sk_invoice_entry)
);

ALTER TABLE payment_snapshot.fact_invoice_entries_snapshot owner to databricks;