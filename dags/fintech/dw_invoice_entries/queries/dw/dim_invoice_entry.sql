WITH revenues AS (
  SELECT
    id_invoice_entry,
    invoice_entry_revenue,
    count(*)
  FROM
    datalake_invoice.invoice_revenues
  GROUP BY 1,2
  HAVING count(*) <= 1
)
SELECT
    ie.id AS sk_invoice_entry,
    ie.id_external_reversed_entry AS sk_invoice_reversed_entry,
    ie.accounting_transaction_identifier,
    ie.entry_type,
    ie.from_account_type,
    ie.to_account_type,
    ie.accounting_account,
    ie.producer,
    ie.description,
    ie.is_rental_paid_in_advance,
    ir.invoice_entry_revenue,
    ie.accrual_year_month,
    ie.due_year_month
    NOW() AS ts_load
FROM
    datalake_retsuko.invoice_entry AS ie
LEFT JOIN
  revenues AS ir
    ON ie.id = ir.id_invoice_entry
