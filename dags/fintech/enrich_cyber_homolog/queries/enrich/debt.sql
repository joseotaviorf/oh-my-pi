SELECT
  c.id_client AS id_debtor,
  c.id_contract,
  c.id_contract_external,
  a.id_invoice,
  a.contract_group AS creditor,
  b.retsuko_status AS payment_status,
  b.due_amount AS invoice_due_amount,
  b.main_amount AS paid_amount,
  b.interest_amount AS interest_fee_amount,
  b.fine_amount AS fine_fee_amount,
  b.main_amount AS debt_amount,
  b.ts_due AS dt_invoice_due,
  NOW() AS ts_load
FROM datalake_cyber_clean.historical_agreements AS a
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON a.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.bill AS b
  ON a.id_invoice = b.id_invoice AND invoice_or_entry = "Invoice"
