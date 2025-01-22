WITH invoices AS (
  SELECT
    id_contract,
    id_invoice,
    creditor,
    our_number,
    LOWER(purpose) AS purpose,
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
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice, contract_group ORDER BY COALESCE(ts_update, MAKE_DATE(year,month,day)) DESC) = 1
),
invoices_negotiated AS (
  SELECT
    COALESCE(h.id_invoice, c.id_invoice) AS id_invoice,
    COALESCE(h.id_contract, c.id_contract) AS id_contract,
    COALESCE(REGEXP_REPLACE(h.id_client,r'\.|\-', ''), REGEXP_REPLACE(c.id_client,r'\.|\-', '')) AS id_client,
    COALESCE(h.creditor, c.creditor) AS creditor,
    COALESCE(h.invoice_due_amount, c.invoice_main_amount) AS due_amount,
    COALESCE(h.invoice_interest_amount, c.invoice_interest_amount) AS interest_amount,
    COALESCE(h.invoice_fine_amount, c.invoice_fine_amount) AS fine_amount
  FROM datalake_cyber_clean.historical_agreements AS h
  FULL OUTER JOIN datalake_cyber_clean.campaign_contracts AS c
    ON h.id_invoice = c.id_invoice AND h.id_contract = c.id_contract
  QUALIFY ROW_NUMBER() OVER(PARTITION BY COALESCE(h.id_invoice, c.id_invoice) ORDER BY COALESCE(h.id_agreement, c.id_offer) ASC) = 1
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
