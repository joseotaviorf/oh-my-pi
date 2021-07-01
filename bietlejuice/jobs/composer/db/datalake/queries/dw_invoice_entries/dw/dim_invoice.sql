SELECT 
    il.id_invoice AS sk_invoice,
    il.invoice_frequency AS frequency,
    il.payment_status,
    il.invoice_user AS user,
    i.due_amount AS due_amount,
    i.paid_amount AS paid_amount,   
    i.accrual_year_month AS accrual_year_month,
    i.ts_created AS ts_created,
    DATE(il.ts_sent) AS dt_sent,
    DATE(il.ts_due) AS dt_due,
    DATE(il.ts_paid) AS dt_paid,
    NOW() AS ts_load
FROM datalake_retsuko.invoice il 
LEFT JOIN datalake_retsuko_clean.invoice i 
    ON il.id_invoice = i.id_external
