WITH invoices AS (
  SELECT
    id_contract,
    id_invoice,
    creditor,
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
    id_contract,
    REGEXP_REPLACE(id_client,r'\.|\-', '') AS id_client,
    creditor,
    invoice_due_amount AS due_amount,
    invoice_interest_amount AS interest_amount,
    invoice_fine_amount AS fine_amount
  FROM datalake_cyber_clean.historical_agreements
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice ORDER BY id_agreement ASC) = 1
)
SELECT
  COALESCE(i.id_invoice, b.id_invoice) AS id_invoice,
  COALESCE(b.id_contract, i.id_contract) AS id_contract_cyber,
  COALESCE(c.id_contract_external, SPLIT(COALESCE(b.id_contract, i.id_contract),r'\.')[0]) AS id_contract,
  COALESCE(i.id_client, c.id_client) AS id_debtor,
  COALESCE(i.creditor, b.creditor) AS creditor,
  b.our_number,
  b.purpose,
  b.retsuko_status AS payment_status,
  b.invoice_status,
  b.pause_reason,
  b.is_tenant_first_invoice,
  b.has_previously_negotiated,
  b.accrual_year_month,
  COALESCE(i.due_amount, b.due_amount) AS due_amount,
  COALESCE(i.interest_amount, b.interest_amount) AS interest_fee_amount,
  COALESCE(i.fine_amount, b.fine_amount) AS fine_fee_amount,
  b.main_amount AS debt_amount,
  b.ts_creation,
  b.ts_due AS dt_invoice_due,
  b.ts_limit_pause,
  NOW() AS ts_load
FROM invoices_negotiated AS i
LEFT JOIN invoices AS b
  ON b.id_invoice = i.id_invoice
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON COALESCE(i.id_contract, b.id_contract) = c.id_contract
