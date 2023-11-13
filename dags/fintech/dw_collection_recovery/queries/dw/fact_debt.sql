WITH deduplicate_creditor_pending AS (
  SELECT DISTINCT
    CASE
      WHEN id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN id_creditor IN (3,5) THEN "IQ QuintoCred"
      WHEN id_creditor IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    id_creditor,
    id_contract,
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
      WHEN id_creditor IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    id_creditor,
    id_contract,
    id_installment,
    installment_code
  FROM datalake_recupera_clean.complementary_records
),
debts AS (
  SELECT
    COALESCE(cp.creditor, cr.creditor) AS creditor,
    COALESCE(cp.id_contract, cr.id_contract) AS id_contract,
    COALESCE(cp.id_installment, cr.id_installment) AS id_invoice,
    COALESCE(cp.id_creditor, cr.id_creditor) AS id_creditor,
    cp.installment_code AS id_negotiation_recupera,
    cp.dt_created
  FROM deduplicate_creditor_pending AS cp
  FULL OUTER JOIN deduplicate_complementary_records AS cr
    ON cp.id_contract = cr.id_contract
      AND cp.id_installment  = cr.id_installment
),
quintocred AS (
    SELECT
        o.id_occurrence,
        o.due_amount,
        o.paid_amount,
        o.ts_paid,
        COALESCE(o.dt_due, o.dt_due_legacy) AS dt_due_final,
        j.desc_lvl_1 AS status
    FROM datalake_velo.occurrence AS o
    LEFT JOIN datalake_velo.junk AS j
        ON o.id_occurrence_status = j.id_junk
)

SELECT DISTINCT
  CONCAT(id_creditor, '-', id_invoice) AS sk_debt,
  BIGINT(d.id_contract) AS id_contract,
  BIGINT(d.id_invoice) AS id_invoice,
  d.creditor AS creditor,
  COALESCE(i.status, LOWER(q.status)) AS invoice_payment_status,
  i.substatus AS invoice_status,
  COALESCE(ABS(i.due_amount), q.due_amount) AS invoice_due_amount,
  COALESCE(i.paid_amount, q.paid_amount) AS invoice_paid_amount,
  DATE(COALESCE(i.ts_due, q.dt_due_final)) AS invoice_dt_due,
  DATE(COALESCE(i.ts_paid, q.ts_paid)) AS invoice_dt_paid,
  NOW() AS ts_load
FROM debts AS d
LEFT JOIN datalake_retsuko.invoice AS i
  ON d.id_invoice = i.id_external
LEFT JOIN quintocred AS q
  ON d.id_invoice = q.id_occurrence
