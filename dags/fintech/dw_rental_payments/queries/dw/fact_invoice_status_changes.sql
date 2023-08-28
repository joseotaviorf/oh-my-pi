WITH invoice_data AS (
  SELECT
    id_external AS sk_invoice,
    id_contract AS sk_contract,
    ABS(due_amount) AS invoice_due_amount,
    IF(status = 'written-down', TRUE, FALSE) AS is_written_down,
    DATE(ts_created) AS dt_created,
    DATE(ts_due) AS dt_due,
    DATE(ts_paid) AS dt_paid,
    DATE(ts_canceled) AS dt_canceled
  FROM
    datalake_retsuko.invoice
  WHERE
    status IN ('open', 'paid', 'canceled', 'written-down')
    AND due_amount <= 0
),
union_reference_date AS (
  SELECT
    sk_invoice,
    sk_contract,
    is_written_down,
    "CREATION DATE" AS cohort_type,
    invoice_due_amount,
    DATE_TRUNC('MONTH', dt_created) AS dt_cohort,
    dt_due,
    dt_paid,
    dt_canceled
  FROM
    invoice_data

  UNION ALL

  SELECT
    sk_invoice,
    sk_contract,
    is_written_down,
    "DUE DATE" AS cohort_type,
    invoice_due_amount,
    DATE_TRUNC('MONTH', dt_due) AS dt_cohort,
    dt_due,
    dt_paid,
    dt_canceled
  FROM
    invoice_data

),
invoice_status_mob AS (
  SELECT
    sk_invoice,
    sk_contract,
    is_written_down,
    cohort_type,
    invoice_due_amount,
    GREATEST(DATEDIFF(MONTH, dt_cohort, current_date),0) AS max_mobs,
    IF(dt_paid IS NOT NULL, GREATEST(DATEDIFF(MONTH, dt_cohort, dt_paid), 0), NULL) AS mob_paid,
    IF(dt_canceled IS NOT NULL, GREATEST(DATEDIFF(MONTH, dt_cohort, dt_canceled), 0), NULL) AS mob_canceled,
    GREATEST(DATEDIFF(MONTH,dt_cohort,dt_due),0) AS mob_due,
    dt_cohort
  FROM
    union_reference_date
),
mob_array AS (
  SELECT
    EXPLODE(ARRAY(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)) AS mob
)

SELECT
  invoice.sk_invoice,
  invoice.sk_contract,
  mobs.mob,
  invoice.cohort_type,
  CASE
    WHEN mobs.mob >= invoice.mob_canceled THEN 'CANCELADA'
    WHEN mobs.mob >= invoice.mob_paid
      AND invoice.is_written_down THEN 'BAIXADA'
    WHEN mobs.mob >= invoice.mob_paid THEN 'PAGA'
    WHEN mobs.mob < invoice.mob_due THEN 'A VENCER'
    ELSE 'VENCIDA'
  END AS status,
  invoice.invoice_due_amount,
  invoice.dt_cohort,
  NOW() AS ts_load
FROM
  invoice_status_mob AS invoice
CROSS JOIN
  mob_array AS mobs
WHERE
  mobs.mob <= invoice.max_mobs
