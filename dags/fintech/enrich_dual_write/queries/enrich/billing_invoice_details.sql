WITH aggregate_invoice_entries AS (
  SELECT
      id_invoice,
      COUNT(id) AS total_entries,
      SUM(amount) AS total_entry_amount
  FROM
      datalake_billing_clean.entry
  GROUP BY
      id_invoice
)

SELECT
    i.id AS id_billing_invoice,
    e.id AS id_billing_entry,
    i.id_account,
    i.id_contract,
    CONCAT_WS(
        '_',
        i.id_account,
        i.dt_accrual_year_month,
        i.purpose
    ) AS id_account_invoice_purpose,
    "billing" AS source,
    i.account_type AS invoice_account_type,
    i.status AS invoice_status,
    i.purpose AS invoice_purpose,
    i.transaction_type AS invoice_transaction_type,
    CAST(i.due_amount AS DECIMAL (10,2)) AS invoice_due_amount,
    i.dt_accrual_year_month AS invoice_accrual_year_month,
    DENSE_RANK() OVER (PARTITION BY c.id ORDER BY i.dt_due ASC, i.id ASC) AS invoice_number,
    e.from_account,
    e.to_account,
    e.bill_item,
    e.description AS bill_item_description,
    e.producer,
    CAST(e.amount AS DECIMAL(10,2)) AS entry_amount,
    ie.total_entries,
    CAST(ie.total_entry_amount AS DECIMAL(10,2)) AS total_entry_amount,
    DATE(c.ts_signature) AS dt_contract_signature,
    i.dt_due AS dt_invoice_due_date,
    c.ts_charge_started,
    c.ts_charge_ended,
    i.ts_created AS ts_invoice_created,
    i.ts_updated AS ts_invoice_updated,
    e.ts_created AS ts_entry_created,
    e.ts_updated AS ts_entry_updated,
    NOW() AS ts_load
FROM
    datalake_billing_clean.invoice AS i
LEFT JOIN
    datalake_billing_clean.entry AS e
    ON i.id = e.id_invoice
LEFT JOIN aggregate_invoice_entries AS ie
    ON ie.id_invoice = i.id
LEFT JOIN datalake_billing.contract AS c
    ON c.id = i.id_contract
