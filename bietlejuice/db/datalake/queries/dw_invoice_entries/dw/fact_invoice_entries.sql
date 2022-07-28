SELECT
	id AS sk_invoice_entry,
	id_invoice AS sk_invoice,
	id_contract AS sk_contract,
	id_contract_user AS sk_contract_user,
	id_region AS sk_region,
	id_created_date AS sk_created_date,
	id_due_date AS sk_due_date,
	id_paid_date AS sk_paid_date,
	brl_entry_due_amount,
	brl_entry_paid_amount,
    ts_created,
    NOW() AS ts_load
FROM
    datalake_invoice.invoice_entries