WITH invoice_replace AS (
    SELECT
        i.id_external AS id_invoice,
        REPLACE(i.purpose, '-', ' ') AS invoice_frequency,
        COALESCE(REPLACE(i.status, '-', ' '), 'not invoiceable') AS payment_status,
        i.negotiation_status,
        MAX(CASE WHEN REPLACE(af.type, '-', ' ') LIKE '%contract%' AND REPLACE(at.type, '-', ' ') NOT LIKE '%contract%' THEN REPLACE(at.type, '-', ' ')
                WHEN REPLACE(af.type, '-', ' ') NOT LIKE '%contract%' AND REPLACE(at.type, '-', ' ') LIKE '%contract%' THEN REPLACE(af.type, '-', ' ')
                WHEN REPLACE(af.type, '-', ' ') LIKE '%contract%' AND REPLACE(at.type, '-', ' ') LIKE '%contract%' THEN 'contract'
            ELSE NULL
        END) AS invoice_user,
        i.ts_sent,
        i.ts_due,
        i.ts_paid
    FROM datalake_retsuko_clean.invoice i
    LEFT JOIN datalake_retsuko_clean.entry e
            ON e.id_invoice = i.id
    INNER JOIN datalake_retsuko_clean.account af 
        ON e.id_from_account = af.id
    INNER JOIN datalake_retsuko_clean.account at 
        ON e.id_to_account = at.id
    GROUP BY 1,2,3,4,6,7,8
)
SELECT
    ir.id_invoice,
    ir.invoice_frequency,
    ir.payment_status,
    ir.negotiation_status,
    ir.invoice_user,   
    ir.ts_sent,
    ir.ts_due,
    ir.ts_paid
FROM invoice_replace ir
