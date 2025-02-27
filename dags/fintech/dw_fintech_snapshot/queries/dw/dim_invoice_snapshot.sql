SELECT
    sk_invoice,
    frequency,
    payment_status,
    negotiation_status,
    closing_mode,
    paid_via,
    user,
    is_write_off,
    reason,
    due_amount,
    paid_amount,
    accrual_year_month,
    ts_created,
    ts_canceled,
    dt_sent,
    dt_due,
    dt_due_adjusted,
    dt_paid,
    dt_write_off,
    ts_load AS ts_snapshot,
    YEAR(ts_load) AS year,
    MONTH(ts_load) AS month,
    DAY(ts_load) AS day
FROM
    dw_payment.dim_invoice
WHERE
    ts_load IS NOT NULL
