WITH deduplicate_creditor_pending AS (
  SELECT DISTINCT
    CASE
      WHEN id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN id_creditor IN (3,5) THEN "IQ QuintoCred"
      WHEN id_creditor IN (2,6) THEN "PP Quinto Andar"
    END AS creditor,
    id_contract,
    id_customer,
    id_installment,
    installment_code,
    DATE(dt_table_insertion) AS dt_created
  FROM datalake_recupera_clean.creditor_pending
),
deduplicate_complementary_records AS (
  SELECT DISTINCT
    CASE
      WHEN id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN id_creditor IN (3,5) THEN "IQ QuintoCred"
      WHEN id_creditor IN (2,6) THEN "PP Quinto Andar"
    END AS creditor,
    id_contract,
    id_customer,
    id_installment,
    installment_code
  FROM datalake_recupera_clean.complementary_records
),
debts AS (
  SELECT
    COALESCE(cp.creditor, cr.creditor) AS creditor,
    COALESCE(cp.id_contract, cr.id_contract) AS id_contract,
    COALESCE(cp.id_customer, cr.id_customer) AS id_customer,
    COALESCE(cp.id_installment, cr.id_installment) AS id_invoice,
    cp.installment_code AS id_negotiation_recupera,
    cp.dt_created
  FROM deduplicate_creditor_pending AS cp
  FULL OUTER JOIN deduplicate_complementary_records AS cr
    ON cp.id_contract = cr.id_contract
      AND cp.id_customer = cr.id_customer
      AND cp.id_installment  = cr.id_installment
)

SELECT
  DENSE_RANK() OVER(ORDER BY d.id_invoice, d.id_negotiation_recupera) AS sk_debt,
  d.id_negotiation_recupera AS sk_negotiation,
  d.id_customer AS sk_debtor,
  BIGINT(d.id_contract) AS id_contract,
  BIGINT(d.id_invoice) AS id_invoice,
  n.id_negotiation AS id_negotiation_trato_feito,
  d.creditor AS creditor,
  i.status AS invoice_payment_status,
  i.substatus AS invoice_status,
  ABS(i.due_amount) AS invoice_due_amount,
  CASE
    WHEN i.status = "paid" THEN i.paid_amount
    WHEN i.status = "written-down"
      AND d.id_negotiation_recupera IS NOT NULL THEN i.paid_amount
    ELSE NULL
  END AS invoice_paid_amount,
  DATE(i.ts_due) AS invoice_dt_due,
  CASE
    WHEN i.status = "paid" THEN DATE(i.ts_paid)
    WHEN i.status = "written-down"
      AND d.id_negotiation_recupera IS NOT NULL THEN DATE(i.ts_paid)
    ELSE NULL
  END AS invoice_dt_paid,
  NOW() AS ts_load
FROM debts AS d
LEFT JOIN datalake_retsuko.invoice AS i
  ON d.id_invoice = i.id_external
LEFT JOIN datalake_debt_recovery.negotiation AS n
    ON n.id_negotiation_recupera = d.id_negotiation_recupera
