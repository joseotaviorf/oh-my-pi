SELECT 
    sk_invoice,
    frequency,
    payment_status,
    user,
    due_amount,
    paid_amount,   
    accrual_year_month,
    ts_created,
    dt_sent,
    dt_due,
    dt_paid,
    ts_load AS ts_snapshot,
    YEAR(ts_load) AS year,
    MONTH(ts_load) AS month,
    DAY(ts_load) AS day
FROM 
    dw_payment.dim_invoice
WHERE
    DATE(ts_load) = DATE('{year}-{month}-{day}')
