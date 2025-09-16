SELECT
	id,
	account_id AS id_account,
	contract_id AS id_contract, 
	source_invoice_id AS id_source_invoice,
	account_type,
	status,
	sub_status,
	purpose,
	transaction_type,
	payload,
	due_amount,
	accrual_year_month AS dt_accrual_year_month,
	due_date AS dt_due,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_billing_raw.invoice
