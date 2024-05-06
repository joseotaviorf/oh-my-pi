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
        MAX(CASE WHEN REPLACE(af.type, '-', ' ') LIKE '%contract%' AND REPLACE(at.type, '-', ' ') NOT LIKE '%contract%' THEN REPLACE(at.type, '-', ' ')
                WHEN REPLACE(af.type, '-', ' ') NOT LIKE '%contract%' AND REPLACE(at.type, '-', ' ') LIKE '%contract%' THEN REPLACE(af.type, '-', ' ')
                WHEN REPLACE(af.type, '-', ' ') LIKE '%contract%' AND REPLACE(at.type, '-', ' ') LIKE '%contract%' THEN 'contract'
            ELSE NULL
        END) AS invoice_user,
        i.ts_sent,
        i.ts_due,
        i.ts_paid,
        i.ts_canceled
    FROM datalake_retsuko_test.invoice i
    LEFT JOIN datalake_retsuko_test.entry e
            ON e.id_invoice = i.id
    LEFT JOIN datalake_retsuko_test_clean.account af
        ON e.id_from_account = af.id
    LEFT JOIN datalake_retsuko_test_clean.account at
        ON e.id_to_account = at.id
    GROUP BY 1,2,3,4,5,6,7,9,10,11,12
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
