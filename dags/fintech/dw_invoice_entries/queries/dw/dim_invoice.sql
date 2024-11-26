SELECT
    il.id_invoice AS sk_invoice,
    il.invoice_frequency AS frequency,
    il.payment_status,
    il.substatus,
    il.negotiation_status,
    il.closing_mode,
    il.paid_via,
    il.invoice_user AS user,
    i.is_write_off,
    CAST(i.due_amount AS DECIMAL(13,2)) AS due_amount,
    CAST(i.paid_amount AS DECIMAL(13,2)) AS paid_amount,
    i.accrual_year_month AS accrual_year_month,
    i.ts_created AS ts_created,
    i.ts_canceled,
    DATE(il.ts_sent) AS dt_sent,
    DATE(il.ts_due) AS dt_due,
    DATE(il.ts_paid) AS dt_paid,
    DATE(i.ts_write_off) AS dt_write_off,
    NOW() AS ts_load
FROM
    datalake_retsuko.invoice_info il
LEFT JOIN
    datalake_retsuko.invoice i
        ON il.id_invoice = i.id_external
