WITH invoices AS (
  SELECT
    id_contract,
    id_invoice,
    contract_group,
    our_number,
    purpose,
    retsuko_status,
    invoice_status,
    pause_reason,
    is_tenant_first_invoice,
    has_previously_negotiated,
    accrual_year_month,
    due_amount,
    interest_amount,
    fine_amount,
    main_amount,
    ts_creation,
    ts_due,
    ts_limit_pause
  FROM datalake_cyber_clean.bill
  WHERE invoice_or_entry = "Invoice"
),
invoices_negotiated AS (
  SELECT
    id_invoice,
    contract_group
  FROM datalake_cyber_clean.historical_agreements
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice ORDER BY id_agreement DESC) = 1
)

SELECT
  b.id_invoice,
  b.id_contract,
  c.id_contract_external,
  c.id_client AS id_debtor,
  b.contract_group AS creditor,
  b.our_number,
  b.purpose,
  b.retsuko_status AS payment_status,
  b.invoice_status,
  b.pause_reason,
  b.is_tenant_first_invoice,
  b.has_previously_negotiated,
  b.accrual_year_month,
  b.due_amount AS due_amount,
  b.interest_amount AS interest_fee_amount,
  b.fine_amount AS fine_fee_amount,
  b.main_amount AS debt_amount,
  b.ts_creation,
  b.ts_due AS dt_invoice_due,
  b.ts_limit_pause,
  NOW() AS ts_load
FROM invoices AS b
INNER JOIN invoices_negotiated AS in
  ON b.id_invoice = in.id_invoice
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON b.id_contract = c.id_contract
