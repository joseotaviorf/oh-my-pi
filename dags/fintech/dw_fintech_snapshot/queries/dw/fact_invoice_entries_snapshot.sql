SELECT
	sk_invoice_entry,
	sk_invoice,
	sk_contract,
	sk_contract_user,
	sk_region,
	sk_created_date,
	sk_due_date,
	sk_paid_date,
	CAST(brl_entry_due_amount AS DECIMAL(10,2)) AS brl_entry_due_amount,
	CAST(brl_entry_paid_amount AS DECIMAL(10,2)) AS brl_entry_paid_amount,
    ts_created,
    ts_load AS ts_snapshot,
    YEAR(ts_load) AS year,
    MONTH(ts_load) AS month,
    DAY(ts_load) AS day
FROM
    dw_payment.fact_invoice_entries
