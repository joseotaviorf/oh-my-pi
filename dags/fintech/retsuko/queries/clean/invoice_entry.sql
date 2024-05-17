SELECT 
    invoice_id AS id_invoice, 
    entry_id AS id_entry,
    invoice_accrual_year_month,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM 
    datalake_retsuko_raw.invoice_entry