WITH base AS (
  SELECT
    di.sk_invoice,
    di.frequency,
    di.payment_status,
    di.user AS invoice_user,
    di.due_amount,
    di.paid_amount,
    di.accrual_year_month,
    SUM(brl_entry_due_amount) AS entry_due_amount,
    SUM(brl_entry_paid_amount) AS entry_paid_amount,
    di.ts_created,
    di.dt_sent,
    di.dt_due,
    di.dt_paid
  FROM dw_payment.dim_invoice AS di
  LEFT JOIN dw_payment.fact_invoice_entries AS fie
    ON fie.sk_invoice = di.sk_invoice
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    10,
    11,
    12,
    13
)
SELECT
  sk_invoice,
  frequency,
  payment_status,
  invoice_user,
  due_amount,
  paid_amount,
  accrual_year_month,
  entry_due_amount,
  entry_paid_amount,
  ts_created,
  dt_sent,
  dt_due,
  dt_paid
FROM base