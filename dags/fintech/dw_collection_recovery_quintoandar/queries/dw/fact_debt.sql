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
  SELECT
    id_invoice,
    id_contract,
    CASE
      WHEN debtor = "rental_contract_landlord" THEN "PP QuintoAndar"
      WHEN debtor = "rental_contract_tenant" THEN "IQ QuintoAndar"
    END AS creditor,
    external_status AS invoice_status,
    external_sub_status AS sub_status,
    due_amount,
    interest_fee_amount,
    fine_fee_amount,
    discount_amount,
    debt_amount,
    paid_amount,
    dt_due,
    dt_paid,
    dt_created,
    "Trato Feito" AS source
  FROM datalake_debt_recovery.debt
  WHERE debtor != "velo_delinquency_tenant"
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice ORDER BY dt_debt_created DESC) = 1
),
recupera_debts AS (
  SELECT DISTINCT
    COALESCE(cp.id_invoice, cr.id_invoice, crwd.id_invoice) AS id_invoice,
    COALESCE(cp.id_contract, cr.id_contract, crwd.id_contract) AS id_contract,
    CASE
      WHEN COALESCE(cp.id_creditor, cr.id_creditor, crwd.id_creditor) IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN COALESCE(cp.id_creditor, cr.id_creditor, crwd.id_creditor) IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    "Recupera" AS source
  FROM deduplicate_creditor_pending AS cp
  FULL OUTER JOIN deduplicate_complementary_records AS cr
      ON cp.id_contract = cr.id_contract
      AND cp.id_invoice  = cr.id_invoice
  FULL OUTER JOIN deduplicate_complementary_records_written_down AS crwd
      ON cp.id_contract = crwd.id_contract
      AND cp.id_invoice  = crwd.id_invoice
),
cyber_debts AS (
  SELECT
    id_invoice,
    id_contract,
    creditor,
    invoice_status,
    due_amount,
    interest_fee_amount,
    fine_fee_amount,
    debt_amount,
    dt_invoice_due AS dt_due,
    "Cyber" AS source
  FROM datalake_cyber_homolog.debt_negotiated
),
debts AS (
  SELECT
    COALESCE(tf.id_invoice, cd.id_invoice, rd.id_invoice) AS id_invoice,
    COALESCE(tf.id_contract, cd.id_contract, rd.id_contract) AS id_contract,
    COALESCE(tf.creditor, cd.creditor, rd.creditor) AS creditor,
    COALESCE(tf.invoice_status, cd.invoice_status) AS invoice_status,
    COALESCE(tf.due_amount, cd.due_amount) AS due_amount,
    COALESCE(tf.interest_fee_amount, cd.interest_fee_amount) AS interest_fee_amount,
    COALESCE(tf.fine_fee_amount, cd.fine_fee_amount) AS fine_fee_amount,
    tf.discount_amount,
    COALESCE(tf.debt_amount, cd.debt_amount) AS debt_amount,
    tf.paid_amount,
    COALESCE(tf.dt_due, cd.dt_due) AS dt_due,
    tf.dt_paid,
    COALESCE(tf.source, cd.source, rd.source) AS source
  FROM trato_feito_debts AS tf
  FULL OUTER JOIN cyber_debts AS cd
    ON tf.id_invoice = cd.id_invoice
  FULL OUTER JOIN recupera_debts AS rd
    ON tf.id_invoice = rd.id_invoice
),
retsuko AS (
  SELECT
    i.id_contract_external AS id_contract,
    i.id_external AS id_invoice,
    IF(ii.invoice_user = "landlord", "PP QuintoAndar", "IQ QuintoAndar") AS creditor,
    i.status AS invoice_status,
    i.payment_status,
    i.substatus AS sub_status,
    ABS(i.due_amount) AS due_amount,
    i.paid_amount AS paid_amount,
    DATE(i.ts_due) AS dt_due,
    DATE(i.ts_paid) AS dt_paid,
    'Retsuko' AS source
  FROM datalake_retsuko.invoice AS i
  LEFT JOIN datalake_retsuko.invoice_info AS ii
    ON i.id_external = ii.id_invoice
)
SELECT
  CONCAT(COALESCE(d.id_contract, r.id_contract), "-", d.id_invoice) AS sk_debt,
  COALESCE(d.id_contract, r.id_contract) AS id_contract,
  d.id_invoice,
  COALESCE(r.creditor, d.creditor) AS creditor,
  r.payment_status,
  COALESCE(r.invoice_status, d.invoice_status) AS invoice_status,
  r.sub_status AS sub_status,
  COALESCE(r.due_amount, d.due_amount) AS due_amount,
  d.interest_fee_amount,
  d.fine_fee_amount,
  d.discount_amount,
  d.debt_amount,
  COALESCE(r.paid_amount, d.paid_amount) AS paid_amount,
  COALESCE(r.source, d.source) AS source,
  COALESCE(r.dt_due, d.dt_due) AS dt_due,
  COALESCE(r.dt_paid, d.dt_paid) AS dt_paid,
  NOW() AS ts_load
FROM debts AS d
INNER JOIN retsuko AS r
  ON d.id_invoice = r.id_invoice
