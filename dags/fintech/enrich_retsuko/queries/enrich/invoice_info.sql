WITH invoice_replace AS (
    SELECT
        i.id_external AS id_invoice,
        REPLACE(i.purpose, '-', ' ') AS invoice_frequency,
        COALESCE(REPLACE(i.status, '-', ' '), 'not invoiceable') AS payment_status,
        CASE WHEN i.substatus = 'none' THEN NULL
            ELSE i.substatus END AS substatus,
        i.negotiation_status,
        i.closing_mode,
        i.paid_via,
        REPLACE(ai.type, '-', ' ') AS invoice_user,
        i.ts_sent,
        i.ts_due,
        i.ts_paid,
        i.ts_canceled
    FROM datalake_retsuko.invoice i
    LEFT JOIN datalake_retsuko_clean.account ai
        ON i.id_account = ai.id
)
SELECT
    ir.id_invoice,
    ir.invoice_frequency,
    ir.payment_status,
    ir.substatus,
    ir.negotiation_status,
    ir.closing_mode,
    ir.paid_via,
    ir.invoice_user,
    ir.ts_sent,
    ir.ts_due,
    ir.ts_paid,
    ir.ts_canceled
FROM invoice_replace ir
