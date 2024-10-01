WITH
dim_date AS (
  SELECT DISTINCT
    month_start
  FROM 
    dw_public.dim_date
),
base_delinquency AS (
  SELECT DISTINCT
    id,
    id_type,
    id_propose,
    id_status,
    DATE( d.ts_created ) AS dt_created,
    d.dt_paid,
    d.original_value,
    d.dt_due AS dt_delinquency_due,
    DATE( date_trunc( 'MONTH', d.dt_due ) ) AS month_due_original,
    dd.month_start AS month_dt_due_renewal,
    IF(
      id_type = 4,
      ( original_value / 12 ), 
      original_value 
    ) AS delinquency_monthly_value,
    CASE 
      WHEN amount_paid > 0 
      AND id_type = 4 
        THEN amount_paid / 12
      WHEN amount_paid > 0 
      AND id_type = 0 
        THEN amount_paid
      ELSE 0
    END AS delinquency_amount_paid_monthly,
    d.is_active,
    IF(
        d.is_active,
        1,
        2
    ) AS order_active
  FROM 
    datalake_rental_guarantee_platform_clean.delinquency d
  LEFT JOIN 
    dim_date dd
    ON dd.month_start 
      BETWEEN 
        date_trunc( 'MONTH', d.dt_due ) 
        AND add_months(date_trunc( 'MONTH', d.dt_due ), 11 )
    AND d.id_type = 4
  WHERE
    id_type IN ( 0, 4, 5, 6)
),
delinquency AS (
  SELECT 
    id,
    id_propose,
    is_active,
    month_due_original,
    DATE( COALESCE( month_dt_due_renewal, month_due_original ) ) AS month_delinquency_due,
    COALESCE( month_dt_due_renewal, month_due_original ) < current_date() AS is_overdue,
    dt_created,
    dt_paid,
    delinquency_monthly_value,
    delinquency_amount_paid_monthly,
    CASE 
      WHEN id_status IN (3,7) 
      OR delinquency_monthly_value - delinquency_amount_paid_monthly < 0 
        THEN 0
      ELSE delinquency_monthly_value - delinquency_amount_paid_monthly
    END AS open_amount_delinquency,
    CASE
      WHEN id_status IN (3,7) 
      AND delinquency_amount_paid_monthly < delinquency_monthly_value 
        THEN delinquency_monthly_value - delinquency_amount_paid_monthly 
    END AS discount_value_delinquency,
    CASE
      WHEN id_status = 0	
        THEN 'REGISTERED'
      WHEN id_status = 1
        THEN 'RECOVERING'
      WHEN id_status = 2
        THEN 'PROGRESS'
      WHEN id_status = 3
        THEN 'FINISHED'
      WHEN id_status = 4
        THEN 'UNDER_AGREEMENT'
      WHEN id_status = 5
        THEN 'REQUESTED_AGREEMENT'
      WHEN id_status = 7
        THEN 'FORGIVEN'
    END AS status,
    CASE
      WHEN id_status = 0
        THEN 7
      WHEN id_status = 1
        THEN 3
      WHEN id_status = 2
        THEN 6
      WHEN id_status = 3
        THEN 1
      WHEN id_status = 4
        THEN 4
      WHEN id_status = 5
        THEN 5
      WHEN id_status = 7
        THEN 2
    END AS ordem_status,
    IF(
      id_type = 4,
      'DELINQUENCY_RENEWAL',
      'DELINQUENCY'
    ) AS gateway,
    'DELINQUENCY' AS billing_type,
    ROW_NUMBER() OVER( 
      PARTITION BY id_propose, COALESCE( month_dt_due_renewal, month_due_original ) 
      ORDER BY order_active ASC, delinquency_amount_paid_monthly DESC, dt_paid DESC) AS rn
  FROM 
    base_delinquency
),
total_delinquency_active AS (
  SELECT
    id_propose,
    month_delinquency_due,
    array_join( array_agg( id ), ',' ) id_array_delinquency,
    COUNT( DISTINCT id )  AS total_quantity_delinquency,
    SUM( delinquency_monthly_value ) AS total_amount_delinquency,
    SUM( delinquency_amount_paid_monthly ) AS total_paid_delinquency,
    SUM( discount_value_delinquency ) AS total_discount_value_delinquency,
    SUM( open_amount_delinquency ) AS total_open_amount_delinquency
  FROM 
    delinquency
  WHERE 
    is_active
  GROUP BY 1, 2
)
SELECT
  d.id_propose,
  id,
  'd_delinquency' AS origin_table,
  t.id_array_delinquency, 
  status,
  ordem_status,
  gateway,
  billing_type,
  delinquency_monthly_value,
  delinquency_amount_paid_monthly,
  open_amount_delinquency,
  discount_value_delinquency,
  t.total_quantity_delinquency,
  t.total_amount_delinquency,
  t.total_paid_delinquency,
  t.total_discount_value_delinquency,
  t.total_open_amount_delinquency,
  month_due_original,
  d.month_delinquency_due, 
  is_active AS is_delinquency_active,
  is_overdue,
  dt_created,
  dt_paid
FROM 
  delinquency d
LEFT JOIN 
  total_delinquency_active t
  ON d.id_propose = t.id_propose
  AND d.month_delinquency_due = t.month_delinquency_due
WHERE 
  rn = 1
