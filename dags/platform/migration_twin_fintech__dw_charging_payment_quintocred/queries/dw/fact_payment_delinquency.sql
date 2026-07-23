WITH
base AS (
  SELECT
    id_propose,
    id,
    id_bill,
    origin_table,
    status,
    order_status,
    gateway,
    billing_type,
    category,
    value,
    value_paid,
    is_overdue,
    dt_paid,
    dt_created,
    dt_due
  FROM 
    dw_charging_payment_quintocred.fact_direct_billing

  UNION ALL

  SELECT 
    id_propose,
    id,
    NULL as id_bill,
    origin_table,
    status,
    order_status,
    gateway,
    billing_type,
    category,
    value,
    value_paid,
    is_overdue,
    dt_paid,
    dt_created,
    dt_due
  FROM 
    dw_charging_payment_quintocred.fact_charging_payment
),
base_payment as (
  SELECT
    *
  FROM 
    base
  QUALIFY
    ROW_NUMBER() OVER( 
      PARTITION BY id_propose, date_trunc( 'MONTH', dt_due ) 
      ORDER BY order_status ASC, origin_table ASC 
    ) = 1
)
SELECT 
  p.id_propose AS sk_propose_payment,
  p.id AS sk_transaction,
  p.id_bill,
  COALESCE(p.id_propose,d.id_propose) AS sk_propose_charge,
  d.id AS sk_delinquency,
  d.id_array_delinquency,
  d.id_propose AS sk_propose_delinquency,
  p.origin_table,
  p.status AS status_payment,
  p.gateway AS gateway_payment,
  p.billing_type AS billing_type_payment,
  d.status AS status_delinquency,
  d.gateway AS gateway_delinquency,
  d.total_amount_delinquency,
  d.delinquency_monthly_value,
  d.delinquency_amount_paid_monthly,
  d.total_paid_delinquency,
  d.open_amount_delinquency,
  d.total_open_amount_delinquency,
  d.discount_value_delinquency,
  d.total_discount_value_delinquency,
  p.value,
  p.value_paid,
  CASE 
    WHEN d.id_propose IS NOT NULL 
    AND p.id_propose IS NULL 
      THEN FALSE
    WHEN d.id_propose IS NOT NULL 
    AND p.id_propose IS NOT NULL
      THEN TRUE
  END AS is_delinquency_charge_related,
  d.is_delinquency_active,
  p.is_overdue,
  COALESCE(date_trunc('month',p.dt_due),d.month_delinquency_due) AS month_charge,
  d.month_due_original,
  d.month_delinquency_due,
  d.dt_paid AS dt_paid_delinquency,
  p.dt_created AS dt_created_payment,
  p.dt_due AS dt_due_payment,
  p.dt_paid AS dt_paid_payment,
  NOW() AS ts_load
FROM
  base_payment p
FULL OUTER JOIN 
  dw_charging_payment_quintocred.fact_delinquecy d
  ON p.id_propose = d.id_propose
  AND date_trunc( 'MONTH', p.dt_due ) = d.month_delinquency_due
