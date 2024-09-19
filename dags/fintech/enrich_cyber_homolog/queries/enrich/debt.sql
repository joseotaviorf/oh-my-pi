SELECT
  a.id_invoice,
  c.id_contract,
  c.id_contract_external,
  c.id_client AS id_debtor,
  a.contract_group AS creditor,
  b.our_number,
  b.purpose,
  b.retsuko_status AS payment_status,
  b.invoice_status,
  b.pause_reason,
  b.accrual_year_month,
  b.due_amount AS due_amount,
  b.interest_amount AS interest_fee_amount,
  b.fine_amount AS fine_fee_amount,
  b.main_amount AS debt_amount,
  b.ts_creation,
  b.ts_due AS dt_invoice_due,
  b.ts_limit_pause,
  NOW() AS ts_load
FROM datalake_cyber_clean.historical_agreements AS a
INNER JOIN datalake_cyber_clean.bill AS b
  ON a.id_invoice = b.id_invoice AND b.invoice_or_entry = "Invoice"
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON a.id_contract = c.id_contract
