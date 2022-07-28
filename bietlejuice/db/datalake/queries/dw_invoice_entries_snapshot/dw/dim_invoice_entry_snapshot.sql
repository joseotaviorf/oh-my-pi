SELECT 
    sk_invoice_entry,
    entry_type,
    from_account_type,
    to_account_type,
    accounting_account,
    producer,
    description,
    invoice_entry_revenue,
    accrual_year_month,
    ts_load AS ts_snapshot,
    YEAR(ts_load) AS year,
    MONTH(ts_load) AS month,
    DAY(ts_load) AS day
FROM 
    dw_payment.dim_invoice_entry
WHERE
    ts_load IS NOT NULL