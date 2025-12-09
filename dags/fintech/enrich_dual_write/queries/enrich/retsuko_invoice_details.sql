WITH aggregate_invoice_entries AS (
  SELECT
      id_invoice,
      COUNT(id) AS total_entries,
      SUM(amount) AS total_entry_amount
  FROM
      datalake_retsuko_clean.entry
  GROUP BY
      id_invoice
)

SELECT
    i.id_external AS id_retsuko_invoice,
    e.id AS id_retsuko_entry,
    a.id_external AS id_account,
    c.id_external AS id_contract,
    CONCAT_WS(
        '_',
        a.id_external,
        i.accrual_year_month,
        i.purpose
    ) AS id_account_invoice_purpose,
    "retsuko" AS source,
    a.type AS invoice_account_type,
    i.status AS invoice_status,
    i.purpose AS invoice_purpose,
    i.due_amount AS invoice_due_amount,
    i.accrual_year_month AS invoice_accrual_year_month,
    DENSE_RANK() OVER (PARTITION BY c.id ORDER BY i.ts_due ASC, i.id_external ASC) AS invoice_number,
    from_account.id_external AS from_account,
    from_account.type AS from_account_type,
    to_account.id_external AS to_account,
    to_account.type AS to_account_type,
    REPLACE(e.bill_item, 'entry.bill-item/', '') AS bill_item,
    e.description AS bill_item_description,
    e.producer,
    e.amount AS entry_amount,
    ie.total_entries,
    ie.total_entry_amount,
    DATE(c.ts_signature) AS dt_contract_signature,
    DATE(i.ts_due) AS dt_invoice_due_date,
    c.ts_charge_started,
    c.ts_charge_ended,
    i.ts_created AS ts_invoice_created,
    i.ts_retsuko_updated AS ts_invoice_updated,
    e.ts_created AS ts_entry_created,
    e.ts_retsuko_updated AS ts_entry_updated,
    NOW() AS ts_load
FROM
    datalake_retsuko_clean.invoice AS i
LEFT JOIN
    datalake_retsuko_clean.entry AS e
    ON i.id = e.id_invoice
LEFT JOIN
    datalake_retsuko_clean.contract AS c
    ON i.id_contract = c.id
LEFT JOIN aggregate_invoice_entries AS ie
    ON ie.id_invoice = i.id
LEFT JOIN
    datalake_retsuko_clean.account AS a
    ON a.id = i.id_account
LEFT JOIN
  datalake_retsuko_clean.account AS from_account
  ON from_account.id = e.id_from_account
LEFT JOIN
  datalake_retsuko_clean.account AS to_account
  ON to_account.id = e.id_to_account
