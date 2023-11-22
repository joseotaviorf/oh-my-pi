WITH deduplicate_creditor_pending AS (
  SELECT DISTINCT
    CASE
      WHEN id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN id_creditor IN (3,5) THEN "IQ QuintoCred"
      WHEN id_creditor IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    CASE
      WHEN id_creditor IN (1,4,7,8,9) THEN 1
      WHEN id_creditor IN (2,6) THEN 2
      ELSE id_creditor
    END AS id_creditor,
    id_customer,
    id_installment
  FROM datalake_recupera_clean.creditor_pending
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY dt_table_insertion DESC, ts_load DESC) = 1
),
deduplicate_complementary_records AS (
  SELECT DISTINCT
    CASE
      WHEN id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN id_creditor IN (3,5) THEN "IQ QuintoCred"
      WHEN id_creditor IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    CASE
      WHEN id_creditor IN (1,4,7,8,9) THEN 1
      WHEN id_creditor IN (2,6) THEN 2
      ELSE id_creditor
    END AS id_creditor,
    id_customer,
    id_installment
  FROM datalake_recupera_clean.complementary_records
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_last_debt_update DESC) = 1
),
debts AS (
  SELECT
    COALESCE(cp.creditor, cr.creditor) AS creditor,
    COALESCE(cp.id_creditor, cr.id_creditor) AS id_creditor,
    COALESCE(cp.id_customer, cr.id_customer) AS id_customer,
    COALESCE(cp.id_installment, cr.id_installment) AS id_invoice
  FROM deduplicate_creditor_pending AS cp
  FULL OUTER JOIN deduplicate_complementary_records AS cr
    ON cp.id_installment  = cr.id_installment
),
union_quintoandar_quintocred AS (
  SELECT
    i.id_contract_external AS id_contract,
    i.id_external AS id_invoice,
    IF(ii.invoice_user = "landlord", 2, 1) AS id_creditor,
    i.status AS invoice_payment_status,
    i.substatus AS invoice_status,
    ABS(i.due_amount) AS invoice_due_amount,
    i.paid_amount AS invoice_paid_amount,
    DATE(i.ts_due) AS invoice_dt_due,
    DATE(i.ts_paid) AS invoice_dt_paid
  FROM datalake_retsuko.invoice AS i
  LEFT JOIN datalake_retsuko.invoice_info AS ii
    ON i.id_external = ii.id_invoice

  UNION ALL

  SELECT
    o.id_propose AS id_contract,
    o.id_occurrence AS id_invoice,
    IF(INT(o.id_propose) < 5000000, 3 , 5) AS id_creditor,
    j.desc_lvl_1 AS invoice_payment_status,
    NULL AS invoice_status,
    o.due_amount AS invoice_due_amount,
    o.paid_amount AS invoice_paid_amount,
    DATE(COALESCE(o.dt_due, o.dt_due_legacy)) AS invoice_dt_due,
    DATE(o.ts_paid) AS invoice_dt_paid
  FROM datalake_velo.occurrence AS o
  LEFT JOIN datalake_velo.junk AS j
    ON o.id_occurrence_status = j.id_junk
)

SELECT DISTINCT
  CONCAT(d.id_creditor, "-", u.id_contract, "-", u.id_invoice) AS sk_debt,
  d.id_customer AS sk_debtor,
  u.id_contract,
  u.id_invoice,
  d.creditor AS creditor,
  u.invoice_payment_status,
  u.invoice_status,
  u.invoice_due_amount,
  u.invoice_paid_amount,
  u.invoice_dt_due,
  u.invoice_dt_paid,
  NOW() AS ts_load
FROM debts AS d
INNER JOIN union_quintoandar_quintocred AS u
  ON d.id_invoice = u.id_invoice
   AND d.id_creditor = u.id_creditor
