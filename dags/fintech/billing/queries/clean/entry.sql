SELECT
	id,
	invoice_id AS id_invoice,
	source_entry_id AS id_source_entry,
	description,
	status,
	from_account,
	to_account,
	bill_item,
	producer,
	transaction_type,
	accounting_transaction_identifier,
	amount,
	accrual_year_month AS dt_accrual_year_month,
	due_year_month AS dt_due_year_month,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_billing_raw.entry
-- This filter ensures that only records created after the billing cleanup are considered.
WHERE created_at > '2026-01-21'
