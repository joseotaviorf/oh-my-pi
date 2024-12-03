WITH
base_payment_asaas AS (
  SELECT 
    IF(
      regexp_extract( description, '(?i)proposta\\s*(\\d+)', 1 ) > 0, 
      regexp_extract( description, '(?i)proposta\\s*(\\d+)', 1 ),
      regexp_extract( description, '(\\d+)', 1 )
    ) AS id_propose,
    id,
    description, 
    dt_created,
    dt_due,
    billint_type,
    status,
    value,
    dt_payment,
    CAST( NULL AS VARCHAR (20) ) AS category
  FROM 
    datalake_velo_asaas_clean.payments asaas
  INNER JOIN 
    dw_velo.fact_velo_propose p
    ON  IF(
        regexp_extract( description, '(?i)proposta\\s*(\\d+)', 1 ) > 0,
        regexp_extract( description, '(?i)proposta\\s*(\\d+)', 1 ),
        regexp_extract( description, '(\\d+)', 1 )
        ) = p.sk_propose AND p.is_contract
),
base_payment AS (
  SELECT
    'a_payment' AS origin_table,
    sk_propose AS id_propose, 
    sk_payment AS id,
    due_amount AS value,
    CASE 
      WHEN status_pay.desc_lvl_1 IN ('SUCCESS','RECEIVED','RECEIVED_IN_CASH') 
        THEN value 
      END AS value_paid,
    dt_created,
    dt_due,
    dt_paid,
    status_pay.desc_lvl_1 AS status,
    gateway.desc_lvl_1 AS gateway,
    billing.desc_lvl_1 AS billing_type,
    category.desc_lvl_1 AS category
  FROM 
    dw_velo.fact_velo_payment p
  LEFT JOIN dw_velo.dim_velo_junk status_pay
    ON status_pay.sk_junk = p.sk_status
  LEFT JOIN dw_velo.dim_velo_junk gateway
    ON gateway.sk_junk = p.sk_payment_gateway
  LEFT JOIN dw_velo.dim_velo_junk billing
    ON billing.sk_junk = p.sk_billing_type
  LEFT JOIN dw_velo.dim_velo_junk category
    ON category.sk_junk = p.sk_payment_category
  WHERE 
    p.sk_payment > 0
    AND billing.desc_lvl_1 NOT IN ( 'ANNUAL_CREDIT_CARD' )
    AND gateway.desc_lvl_1 NOT IN ( 'PIXAR' )

  UNION ALL

  SELECT
    'a_payment' AS origin_table,
    p.sk_propose AS id_propose, 
    sk_payment AS id,
    CASE 
      WHEN status_pay.desc_lvl_1 NOT IN ( 'SUCCESS', 'REFUNDED', 'REFUND_PROCESSING', 'CHARGEBACK', 'REVERSED', 'SCHEDULED_REVERSAL' ) 
        AND category.desc_lvl_1 NOT IN  ( 'ACTIVATION' ) 
        AND cp.installments IS NOT NULL
          THEN due_amount/cp.installments 
      WHEN status_pay.desc_lvl_1 NOT IN  ( 'SUCCESS', 'REFUNDED', 'REFUND_PROCESSING', 'CHARGEBACK', 'REVERSED', 'SCHEDULED_REVERSAL' )
        AND category.desc_lvl_1 NOT IN  ('ACTIVATION') 
        AND cp.installments IS NULL 
        AND due_amount / 12 = pv.monthly_guarantee 
          THEN due_amount / 12
      WHEN status_pay.desc_lvl_1 NOT IN  ( 'SUCCESS', 'REFUNDED', 'REFUND_PROCESSING', 'CHARGEBACK', 'REVERSED', 'SCHEDULED_REVERSAL')
        AND category.desc_lvl_1 NOT IN  ('ACTIVATION') 
        AND cp.installments IS NULL 
          THEN due_amount / 1
      ELSE due_amount 
    END AS value,
    CASE 
      WHEN status_pay.desc_lvl_1 IN ( 'SUCCESS', 'RECEIVED', 'RECEIVED_IN_CASH' ) 
        THEN value 
    END AS value_paid,
    dt_created,
    dt_due,
    dt_paid,
    status_pay.desc_lvl_1 AS status,
    gateway.desc_lvl_1 AS gateway,
    billing.desc_lvl_1 AS billing_type,
    category.desc_lvl_1 AS category
  FROM 
    dw_velo.fact_velo_payment p
  LEFT JOIN 
    datalake_rental_guarantee_platform_clean.payment cp
    ON p.sk_payment = cp.id
  LEFT JOIN 
    dw_velo.dim_velo_junk status_pay
    ON status_pay.sk_junk = p.sk_status
  LEFT JOIN dw_velo.dim_velo_junk gateway
    ON gateway.sk_junk = p.sk_payment_gateway
  LEFT JOIN dw_velo.dim_velo_junk billing
    ON billing.sk_junk = p.sk_billing_type
  LEFT JOIN dw_velo.dim_velo_junk category
    ON category.sk_junk = p.sk_payment_category
  LEFT JOIN dw_velo.fact_velo_propose pr
    ON pr.sk_propose = p.sk_propose
  LEFT JOIN dw_velo.dim_velo_propose_values pv
    ON pr.sk_propose_values = pv.sk_propose_values
  WHERE 
    p.sk_payment > 0
    AND ( billing.desc_lvl_1 IN ( 'ANNUAL_CREDIT_CARD' ) OR gateway.desc_lvl_1 IN ( 'PIXAR' ) )

  UNION ALL

  SELECT 
    'b_payment_legacy' AS origin_table,
    sk_propose AS id_propose,
    sk_payment AS id,
    due_amount AS value,
    CASE 
      WHEN status_pay.desc_lvl_1 IN ( 'SUCCESS', 'RECEIVED', 'RECEIVED_IN_CASH' ) 
        THEN value 
    END AS value_paid,
    pl.dt_created,
    dt_due,
    dt_paid,
    status_pay.desc_lvl_1 AS status,
    gateway.desc_lvl_1 AS gateway,
    billing.desc_lvl_1 AS billing_type,
    category.desc_lvl_1 AS category
  FROM
    dw_velo.fact_velo_payment_legacy pl
  LEFT JOIN dw_velo.dim_velo_junk status_pay
    ON status_pay.sk_junk = pl.sk_status
  LEFT JOIN dw_velo.dim_velo_junk gateway
    ON gateway.sk_junk = pl.sk_payment_gateway
  LEFT JOIN dw_velo.dim_velo_junk billing
    ON billing.sk_junk = pl.sk_billing_type
  LEFT JOIN dw_velo.dim_velo_junk category
    ON category.sk_junk = pl.sk_payment_category 
  WHERE
    category.desc_lvl_1 NOT IN ( 'AGREEMENT' )

  UNION ALL

  SELECT 
    "c_asaas" AS origin_table,
    id_propose,
    id,
    value,
    CASE 
      WHEN status IN ( 'RECEIVED','RECEIVED_IN_CASH' ) 
        THEN value 
    END AS value_paid,
    dt_created,
    date( dt_due ) AS dt_due,
    dt_payment AS dt_paid,
    status,
    "ASAAS RAW" AS gateway,
    billint_type AS billing_type,
    category
  FROM 
    base_payment_asaas
),
dim_date AS (
  SELECT DISTINCT
    month_start
  FROM
    dw_public.dim_date
),
base_payment_ajustada AS (
  SELECT DISTINCT
    b.origin_table,
    b.id_propose,
    b.id,
    CASE 
      WHEN dd.month_start IS NOT NULL 
        THEN b.value/12 ELSE b.value 
    END AS value,
    CASE 
      WHEN dd.month_start IS NOT NULL 
        THEN b.value_paid/12 
      ELSE b.value_paid 
    END AS value_paid,
    b.dt_created,
    CASE 
      WHEN dd.month_start IS NOT NULL 
        THEN dd.month_start 
      ELSE b.dt_due 
    END AS dt_due,
    dt_paid,
    status,
    CASE 
      WHEN dd.month_start IS NOT NULL 
        THEN 'ASAAS Anual' 
      ELSE gateway 
    END AS gateway,
    billing_type,
    category
  FROM 
    base_payment b
  LEFT JOIN 
    dw_velo.fact_velo_propose p
    ON b.id_propose = p.sk_propose
  LEFT JOIN 
    dw_velo.dim_velo_propose_values pv
    ON p.sk_propose_values = pv.sk_propose_values
  LEFT JOIN dim_date dd
    ON dd.month_start 
    BETWEEN 
      date_trunc( 'MONTH', b.dt_due ) 
      AND add_months( date_trunc( 'MONTH', b.dt_due ), 11 )
    AND b.value BETWEEN  
      ( pv.annual_guarantee + pv.activator_amount ) * 0.8  
      AND ( pv.annual_guarantee + pv.activator_amount ) * 1.12
    AND ( b.gateway = 'ASAAS' OR b.gateway = 'ASAAS RAW' )
    AND b.status IN ( 'SUCCESS','RECEIVED','RECEIVED_IN_CASH' )
)
SELECT 
  id,
  id_propose,
  'b_payment' AS origin_table,
  status,
  CASE 
    WHEN status IN ('SUCCESS','RECEIVED_IN_CASH','RECEIVED') 
      THEN 1
    WHEN status = 'CONFIRMED' 
      THEN 2
    WHEN status = 'PROCESSING' 
      THEN 3
    WHEN status IN ('REVERSED','SCHEDULED_REVERSAL')  
      THEN 4
    WHEN status IN ('REFUNDED','REFUND_PROCESSING')  
      THEN 5
    WHEN status = 'CHARGEBACK' 
      THEN 6
    WHEN status IN ('REFUSED','EXPIRED')
      THEN 7
    WHEN status = 'PENDING' 
      THEN 8
    WHEN status = 'OVERDUE' 
      THEN 9
    WHEN status = 'IMPROPER_BILLING' 
      THEN 10
    WHEN status = 'ERROR' 
      THEN 11
  END AS order_status,
  CASE 
    WHEN gateway = 'WALLSTREET' 
      THEN billing_type 
    ELSE gateway 
  END AS gateway,
  billing_type,
  category,
  value,
  value_paid,
  DATE( dt_due ) < current_date() is_overdue,
  dt_paid,
  dt_created,
  DATE( dt_due ) AS dt_due
FROM 
  base_payment_ajustada d
WHERE 
  id_propose > 0
QUALIFY
  ROW_NUMBER() OVER( 
    PARTITION BY id_propose, ROUND( value ), date_trunc( 'MONTH', dt_due ) 
    ORDER BY status DESC, origin_table ASC 
  ) = 1
