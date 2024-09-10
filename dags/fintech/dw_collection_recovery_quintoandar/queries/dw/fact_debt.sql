WITH
deduplicate_creditor_pending AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_installment AS id_invoice
  FROM datalake_recupera_clean.creditor_pending
  WHERE
    installment_code IS NOT NULL
    AND id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY dt_table_insertion DESC, ts_load DESC) = 1
),
deduplicate_complementary_records AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_installment AS id_invoice
  FROM datalake_recupera_clean.complementary_records
  WHERE
    installment_code IS NOT NULL
    AND id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_last_debt_update DESC) = 1
),
deduplicate_complementary_records_written_down AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_installment AS id_invoice
  FROM datalake_recupera_clean.complementary_records_written_down
  WHERE
    IF(ASCII(TRIM(installment_code))=0, NULL, installment_code) IS NOT NULL
    AND id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_last_debt_update DESC) = 1
),
trato_feito_debts AS (
  SELECT DISTINCT
    d.id_external AS id_invoice,
    n.id_contract,
    CASE
      WHEN n.debtor = "rental_contract_landlord" THEN "PP QuintoAndar"
      WHEN n.debtor = "rental_contract_tenant" THEN "IQ QuintoAndar"
    END AS creditor,
    d.interest_fee_amount,
    d.fine_fee_amount,
    d.discount_amount,
    d.original_amount + d.interest_fee_amount + d.fine_fee_amount - d.discount_amount AS debt_amount
  FROM datalake_trato_feito_clean.debt AS d
  LEFT JOIN datalake_debt_recovery.negotiation AS n
    ON d.id_negotiation = n.id_negotiation
  WHERE
    d.id_negotiation IS NOT NULL
    AND n.debtor != "velo_delinquency_tenant"
  QUALIFY ROW_NUMBER() OVER(PARTITION BY d.id_external ORDER BY d.ts_created DESC) = 1
),
recupera_debts AS (
  SELECT DISTINCT
    COALESCE(cp.id_invoice, cr.id_invoice, crwd.id_invoice) AS id_invoice,
    CASE
      WHEN COALESCE(cp.id_creditor, cr.id_creditor, crwd.id_creditor) IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN COALESCE(cp.id_creditor, cr.id_creditor, crwd.id_creditor) IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    COALESCE(cp.id_contract, cr.id_contract, crwd.id_contract) AS id_contract
  FROM deduplicate_creditor_pending AS cp
  FULL OUTER JOIN deduplicate_complementary_records AS cr
      ON cp.id_contract = cr.id_contract
      AND cp.id_invoice  = cr.id_invoice
  FULL OUTER JOIN deduplicate_complementary_records_written_down AS crwd
      ON cp.id_contract = crwd.id_contract
      AND cp.id_invoice  = crwd.id_invoice
),
debts AS (
 SELECT
    COALESCE(tfd.creditor, rd.creditor) AS creditor,
    COALESCE(tfd.id_contract, rd.id_contract) AS id_contract,
    COALESCE(tfd.id_invoice, rd.id_invoice) AS id_invoice,
    tfd.interest_fee_amount,
    tfd.fine_fee_amount,
    tfd.discount_amount,
    tfd.debt_amount
  FROM trato_feito_debts AS tfd
  FULL OUTER JOIN recupera_debts AS rd
    ON rd.id_contract = tfd.id_contract
        AND rd.id_invoice  = tfd.id_invoice
),
retsuko AS (
  SELECT
    i.id_contract_external AS id_contract,
    i.id_external AS id_invoice,
    IF(ii.invoice_user = "landlord", "PP QuintoAndar", "IQ QuintoAndar") AS creditor,
    i.status AS invoice_payment_status,
    i.substatus AS invoice_status,
    ABS(i.due_amount) AS invoice_due_amount,
    i.paid_amount AS invoice_paid_amount,
    DATE(i.ts_due) AS dt_invoice_due,
    DATE(i.ts_paid) AS dt_invoice_paid
  FROM datalake_retsuko.invoice AS i
  LEFT JOIN datalake_retsuko.invoice_info AS ii
    ON i.id_external = ii.id_invoice
)
SELECT DISTINCT
  CONCAT(COALESCE(u.id_contract, d.id_contract), "-", d.id_invoice) AS sk_debt,
  COALESCE(u.id_contract, d.id_contract) AS id_contract,
  d.id_invoice,
  d.creditor,
  u.invoice_payment_status,
  u.invoice_status,
  u.invoice_due_amount,
  u.invoice_paid_amount,
  d.interest_fee_amount,
  d.fine_fee_amount,
  d.discount_amount,
  d.debt_amount,
  u.dt_invoice_due,
  u.dt_invoice_paid,
  NOW() AS ts_load
FROM debts AS d
LEFT JOIN retsuko AS u
  ON d.id_invoice = u.id_invoice
   AND d.creditor = u.creditor
