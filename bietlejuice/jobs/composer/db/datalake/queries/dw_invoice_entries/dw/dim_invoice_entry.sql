SELECT 
    ie.id AS sk_invoice_entry,
    ie.entry_type,
    ie.from_account_type,
    ie.to_account_type,
    ie.accounting_account,
    ie.producer,
    ie.description,
    ir.invoice_entry_revenue,
    ie.accrual_year_month,
    NOW() AS ts_load
FROM datalake_retsuko.invoice_entry AS ie
LEFT JOIN datalake_invoice.invoice_revenues AS ir
    ON ie.id = ir.id_invoice_entry