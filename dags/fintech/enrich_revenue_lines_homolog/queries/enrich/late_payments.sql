WITH payment AS (
    SELECT
        CONCAT(ies.id, ies.id_contract, ri.accrual_year_month) AS id_late_payments,
        ies.id_contract,
        'payment' AS type_late,
        ies.brl_entry_due_amount AS invoice_theorical_amount,
        CASE
            WHEN ies.id_paid_date > 0 THEN ies.brl_entry_due_amount
            ELSE ies.brl_entry_paid_amount
        END AS invoice_paid_amount,
        ri.accrual_year_month,
        DATE(ies.ts_created) AS dt_created,
        dd_due.date AS dt_due,
        dd_paid.date AS dt_paid
    FROM
        datalake_invoice.invoice_entries AS ies
    INNER JOIN
        datalake_retsuko.invoice_entry AS ie
            ON ies.id = ie.id
    INNER JOIN
        datalake_retsuko.invoice_info AS i
            ON ies.id_invoice = i.id_invoice
    LEFT JOIN
        datalake_retsuko.invoice ri
            ON i.id_invoice = ri.id_external
    LEFT JOIN
        datalake_quintoandar.aux_date AS dd_due
            ON dd_due.id_date = ies.id_due_date
    LEFT JOIN
        datalake_quintoandar.aux_date AS dd_paid
            ON dd_paid.id_date = ies.id_paid_date
    WHERE
        ie.entry_type = 'fine and interest'
        AND ie.from_account_type = 'tenant'
        AND ie.to_account_type = 'contract'
    ),
condo AS (
    SELECT
        CONCAT(ies.id, ies.id_contract, ri.accrual_year_month) AS id_late_payments,
        ies.id_contract,
        'condo' AS type_late,
        ies.brl_entry_due_amount AS invoice_theorical_amount,
        ies.brl_entry_paid_amount AS invoice_paid_amount,
        ri.accrual_year_month,
        DATE(ies.ts_created) AS dt_created,
        dd_due.date AS dt_due,
        dd_paid.date AS dt_paid
    FROM
        datalake_invoice.invoice_entries AS ies
    INNER JOIN
        datalake_retsuko.invoice_entry AS ie
            ON ies.id = ie.id
    INNER JOIN
        datalake_retsuko.invoice_info AS i
            ON ies.id_invoice = i.id_invoice
    LEFT JOIN
        datalake_retsuko.invoice ri
            ON i.id_invoice = ri.id_external
    LEFT JOIN
        datalake_quintoandar.aux_date AS dd_due
            ON dd_due.id_date = ies.id_due_date
    LEFT JOIN
        datalake_quintoandar.aux_date AS dd_paid
            ON dd_paid.id_date = ies.id_paid_date
    WHERE
        ie.entry_type = 'property damage fine'
        AND LOWER(ie.description) LIKE '%quebra contratual%'
        AND ie.from_account_type = 'tenant'
        AND ie.to_account_type = 'contract'
    )
SELECT
    *
FROM payment
UNION
SELECT
    *
FROM condo
