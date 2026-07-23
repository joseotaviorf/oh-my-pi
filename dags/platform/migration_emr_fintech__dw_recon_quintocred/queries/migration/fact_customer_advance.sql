WITH
base_propose AS (
  SELECT DISTINCT
      p.sk_propose,
      pv.activator_amount,
      CASE 
          WHEN is_corrected_robot = TRUE AND monthly_timeline_renewal_corrected = 0 THEN monthly_timeline_renewal
          WHEN is_corrected_robot = TRUE AND monthly_timeline_renewal_corrected > 0 THEN monthly_timeline_renewal_corrected
          ELSE monthly_timeline_renewal
      END AS monthly_guarantee,
      CASE 
          WHEN is_corrected_robot = TRUE AND monthly_timeline_renewal_corrected = 0 THEN monthly_timeline_renewal * 12
          WHEN is_corrected_robot = TRUE AND monthly_timeline_renewal_corrected > 0 THEN monthly_timeline_renewal_corrected * 12
          ELSE monthly_timeline_renewal * 12
      END AS annual_guarantee,
      p.dt_contract_started,
      p.dt_ended_official AS dt_ended,
      p.is_direct_billing
  FROM 
    dw_velo.fact_velo_propose p
  LEFT JOIN 
    dw_velo.dim_velo_propose_values pv
      ON p.sk_propose_values = pv.sk_propose_values
  LEFT JOIN 
    dw_charging_payment_quintocred.fact_payment_full car
      ON car.sk_propose = CAST(p.sk_propose AS VARCHAR(10))
      AND car.month_reference = DATEADD(MONTH, -1, DATE_TRUNC('MONTH', CURRENT_DATE))
  WHERE 
    p.is_contract
),
base_payment AS (
  SELECT
      'payment_ongoing' AS origin_table,
      sk_propose AS id_propose, 
      sk_payment AS id,
      p.id_unicid,
      CAST(due_amount AS DOUBLE) AS value,
      dt_created,
      CAST(dt_due AS DATE) AS dt_due,
      DATE_TRUNC('MONTH', dt_due) AS month_ref_due,
      CAST(dt_paid AS DATE) AS dt_paid,
      status_pay.desc_lvl_1 AS status,
      gateway.desc_lvl_1 AS gateway,
      billing.desc_lvl_1 AS billing_type,
      category.desc_lvl_1 AS category
  FROM 
    dw_velo.fact_velo_payment p
  LEFT JOIN 
    dw_velo.dim_velo_junk status_pay
      ON status_pay.sk_junk = p.sk_status
  LEFT JOIN 
    dw_velo.dim_velo_junk gateway
      ON gateway.sk_junk = p.sk_payment_gateway
  LEFT JOIN 
    dw_velo.dim_velo_junk billing
      ON billing.sk_junk = p.sk_billing_type
  LEFT JOIN 
    dw_velo.dim_velo_junk category
      ON category.sk_junk = p.sk_payment_category
  WHERE 
    p.sk_payment > 0
    AND status_pay.desc_lvl_1 = 'SUCCESS'
    AND gateway.desc_lvl_1 <> 'ASAAS'
    AND billing.desc_lvl_1 <> 'CREDIT_CARD'

  UNION ALL

  SELECT
      'payment_ongoing' AS origin_table,
      p.sk_propose AS id_propose, 
      sk_payment AS id,
      p.id_unicid,
      CAST(due_amount AS DOUBLE) AS value,
      dt_created,
      CAST(dt_due AS DATE) AS dt_due,
      DATE_TRUNC('MONTH', dt_due) AS month_ref_due,
      CAST(dt_paid AS DATE) AS dt_paid,
      status_pay.desc_lvl_1 AS status,
      gateway.desc_lvl_1 AS gateway,
      billing.desc_lvl_1 AS billing_type,
      category.desc_lvl_1 AS category
  FROM 
    dw_velo.fact_velo_payment p
  LEFT JOIN 
    dw_velo.dim_velo_junk status_pay
      ON status_pay.sk_junk = p.sk_status
  LEFT JOIN 
    dw_velo.dim_velo_junk gateway
      ON gateway.sk_junk = p.sk_payment_gateway
  LEFT JOIN 
    dw_velo.dim_velo_junk billing
      ON billing.sk_junk = p.sk_billing_type
  LEFT JOIN 
    dw_velo.dim_velo_junk category
      ON category.sk_junk = p.sk_payment_category
  LEFT JOIN 
    base_propose pv
      ON pv.sk_propose = p.sk_propose
  WHERE 
    p.sk_payment > 0
    AND status_pay.desc_lvl_1 = 'SUCCESS'
    AND gateway.desc_lvl_1 = 'ASAAS'
    AND p.due_amount BETWEEN pv.annual_guarantee * 0.8 AND pv.annual_guarantee * 1.12
),
dt_created_corrected AS (
  SELECT
      id_propose,
      id_unicid,
      MAX(dt_created) AS dt_created_corrigido
  FROM 
    base_payment
  GROUP BY 1, 2
),
payments_table AS (
  SELECT
    bp.id_propose, 
    id,
    bp.id_unicid,
    value,
    dt_created_corrigido as dt_created,
    date_trunc('MONTH', dt_created_corrigido) month_ref_creation,
    dt_due,
    month_ref_due,
    dt_paid,
    status,
    gateway,
    billing_type,
    category
  FROM 
    base_payment bp
  LEFT JOIN 
    dt_created_corrected 
      ON bp.id_propose = dt_created_corrected.id_propose
      AND bp.id_unicid = dt_created_corrected.id_unicid
),
agg_payment_delinquency AS(
  SELECT
      month_ref_creation,
      id_propose,
      gateway,
      MIN(id) AS min_id_payment,
      MAX(dt_created) AS dt_created,
      COUNT(id) AS number_of_payments,
      ARRAY_AGG(DISTINCT category) AS category_eval,
      SUM(value) AS value_payment,
      SUM(value) AS total_paid,
      MIN(dt_due) AS min_dt_due,
      MAX(dt_due) AS max_dt_due,
      MIN(dt_paid) AS min_dt_paid,
      MAX(dt_paid) AS max_dt_paid
  FROM 
    payments_table
  GROUP BY 1, 2, 3

  UNION ALL

  SELECT
      DATE(DATE_TRUNC('MONTH', ts_created)) AS month_ref_creation,
      id_propose,
      'DELINQUENCY' AS gateway,
      MIN(id) AS min_id_payment,
      DATE(ts_created) AS dt_created,
      COUNT(id) AS number_of_payments,
      NULL AS category_eval,
      SUM(original_value) AS value_delinquency,
      IF(SUM(amount_paid) > SUM(original_value), SUM(original_value), SUM(amount_paid)) AS total_paid,
      dt_due AS min_dt_due,
      dt_due AS max_dt_due,
      dt_paid AS min_dt_paid,
      dt_paid AS max_dt_paid
  FROM 
    datalake_rental_guarantee_platform_clean.delinquency d
  LEFT JOIN 
    base_propose pv
      ON pv.sk_propose = d.id_propose
  WHERE 
    id_type = 4
    AND d.original_value BETWEEN pv.annual_guarantee * 0.8 AND pv.annual_guarantee * 1.12
    AND is_active
    AND amount_paid > 0
  GROUP BY 1, 2, 3, 5, 7, 10, 11, 12, 13
),
months_paid_delinquency AS ( 
  SELECT
    IF(
      ROUND(p.total_paid, 1) >= ROUND(pv.annual_guarantee, 1), 12,
      (p.total_paid / pv.monthly_guarantee)
    ) AS months_paid,
    IF(
      ROUND(p.total_paid, 1) >= ROUND(pv.annual_guarantee, 1), 12,
      MOD((p.total_paid / pv.monthly_guarantee), 1)
    ) AS decimal,
    p.month_ref_creation,
    p.id_propose
  FROM 
    agg_payment_delinquency p
  LEFT JOIN 
    base_propose pv
      ON pv.sk_propose = p.id_propose
  WHERE 
    gateway = 'DELINQUENCY'
),
base_all_payment AS (
  SELECT
    pv.*,
    p.*,
    CASE 
        WHEN p.gateway IN ('ASAAS') THEN DATEADD(MONTH, 11, min_dt_due)
        WHEN p.gateway IN ('DELINQUENCY') AND decimal > 0 THEN DATEADD(MONTH, LEAST((CAST(months_paid AS BIGINT) + 1), 11), min_dt_due)
        WHEN p.gateway IN ('DELINQUENCY') THEN DATEADD(MONTH, LEAST(CAST(months_paid AS BIGINT), 11), min_dt_due)
        ELSE max_dt_due
    END AS max_due_date_adjusted,
    CASE 
        WHEN array_contains(category_eval, 'ACTIVATION') THEN 1
        ELSE 0
    END AS flag_has_activation,
    CASE
        WHEN p.gateway IN ('PIXAR','WALLSTREET','CHECKOUT_V2') THEN 12 * (YEAR(max_dt_due) - YEAR(min_dt_due)) + (MONTH(max_dt_due) - MONTH(min_dt_due)) + 1
        WHEN p.gateway IN ('DELINQUENCY') THEN d.months_paid
        WHEN p.gateway IN ('ASAAS') THEN 12
    END AS mobs_in_between_due_dates,
    DATEADD(DAY, -1, DATE_TRUNC('MONTH', CURRENT_DATE)) AS last_day_month_closed
  FROM 
    agg_payment_delinquency p
  LEFT JOIN 
    months_paid_delinquency d
      ON p.id_propose = d.id_propose
      AND p.month_ref_creation = d.month_ref_creation
  LEFT JOIN 
    base_propose pv
      ON pv.sk_propose = p.id_propose
),
lag_month AS (
  SELECT
      *,
      CASE
          WHEN gateway <> 'DELINQUENCY' THEN value_payment - flag_has_activation * activator_amount
          ELSE total_paid
      END AS value_upfront_signatures,
      LAG(max_due_date_adjusted) OVER(PARTITION BY sk_propose ORDER BY min_dt_due) AS lag_month_due_end
  FROM 
    base_all_payment
),
diff_months_charge AS (
  SELECT
      *,
      (YEAR(DATE_TRUNC('MONTH', min_dt_due)) - YEAR(lag_month_due_end)) * 12 + (MONTH(DATE_TRUNC('MONTH', min_dt_due)) - MONTH(lag_month_due_end)) AS diff_months_charge
  FROM 
    lag_month
),
month_appropriation_start AS (
  SELECT 
      sk_propose,
      is_direct_billing,
      last_day_month_closed,
      activator_amount,
      value_upfront_signatures,
      monthly_guarantee,
      annual_guarantee,
      dt_contract_started,
      dt_ended,
      dt_created,
      month_ref_creation,
      min_id_payment,
      bc.flow_type,
      mobs_in_between_due_dates,
      diff_months_charge,
      CASE WHEN diff_months_charge = 0 THEN DATEADD(MONTH, 1, min_dt_due) ELSE min_dt_due END AS month_appropriation_start,
      min_dt_due,
      max_due_date_adjusted,
      CASE WHEN diff_months_charge = 0 THEN DATEADD(MONTH, 1, max_due_date_adjusted) ELSE max_due_date_adjusted END AS max_dt_due,
      min_dt_paid,
      max_dt_paid,
      gateway,
      flag_has_activation,
      value_payment,
      total_paid
  FROM 
    diff_months_charge ba
  LEFT JOIN 
    datalake_rental_guarantee_platform_clean.bill_payment b
      ON b.id_payment = ba.min_id_payment
  LEFT JOIN 
    datalake_rental_guarantee_platform_clean.bill_checkout bc
      ON b.id_bill = bc.id
),
expected_appropriated_months as (
  SELECT
      *,
      CASE 
        WHEN dt_ended IS NOT NULL AND DAY(dt_ended) >= DAY(month_appropriation_start) THEN LEAST(12*(YEAR(dt_ended) - YEAR(month_appropriation_start)) + (MONTH(dt_ended) - MONTH(month_appropriation_start)) + 1, 12)
        WHEN dt_ended IS NOT NULL AND DAY(dt_ended) < DAY(month_appropriation_start) THEN LEAST(12*(YEAR(dt_ended) - YEAR(month_appropriation_start)) + (MONTH(dt_ended) - MONTH(month_appropriation_start)), 12)
        WHEN dt_ended IS NULL THEN LEAST(12*(YEAR(last_day_month_closed) - YEAR(month_appropriation_start)) + (MONTH(last_day_month_closed) - MONTH(month_appropriation_start)) + 1, 12)
        ELSE -99 
      END AS expected_appropriated_months
  FROM 
    month_appropriation_start
),
base AS (
SELECT
    sk_propose,
    is_direct_billing,
    activator_amount,
    monthly_guarantee,
    annual_guarantee,
    dt_contract_started,
    dt_ended,
    dt_created,
    DATE(month_ref_creation) month_ref_creation,
    flow_type,
    min_id_payment,
    ROUND(mobs_in_between_due_dates, 2) mobs_in_between_due_dates,
    DATE(month_appropriation_start) month_appropriation_start,
    DATE(min_dt_due) min_dt_due,
    DATE(max_dt_due) max_dt_due,
    DATE(DATE_TRUNC('MONTH', last_day_month_closed)) month_last_day,
    DATE(min_dt_paid) min_dt_paid,
    DATE(max_dt_paid) max_dt_paid,
    gateway,
    flag_has_activation,
    value_payment AS total_charged,
    total_paid,
    CASE
      WHEN gateway = 'DELINQUENCY' AND (value_payment / mobs_in_between_due_dates) * expected_appropriated_months > total_paid THEN 0
      ELSE value_upfront_signatures
    END value_upfront_signatures,
    CASE 
      WHEN gateway = 'DELINQUENCY' AND ((value_payment / mobs_in_between_due_dates) * expected_appropriated_months) > total_paid THEN FALSE 
      ELSE TRUE 
    END AS has_payment_advance,
    expected_appropriated_months
FROM 
  expected_appropriated_months
WHERE
  (dt_ended IS NULL OR dt_ended >= DATE_TRUNC('MONTH', CURRENT_DATE))
  AND mobs_in_between_due_dates > 1
  AND DATE_TRUNC('MONTH', max_dt_due) >= DATE_TRUNC('MONTH', last_day_month_closed)
  AND ((value_payment / mobs_in_between_due_dates) * expected_appropriated_months > monthly_guarantee * 0.8
        OR (value_payment / mobs_in_between_due_dates) * expected_appropriated_months = 0)
  AND min_dt_paid < DATE_TRUNC('MONTH', CURRENT_DATE)
)
SELECT 
  sk_propose,
  min_id_payment AS id_payment_min,
  flow_type,
  gateway,
  activator_amount,
  monthly_guarantee,
  annual_guarantee,
  total_charged,
  total_paid,
  value_upfront_signatures,
  expected_appropriated_months,
  expected_appropriated_months * (value_upfront_signatures/mobs_in_between_due_dates) AS expected_appropriated_amount,
  mobs_in_between_due_dates - expected_appropriated_months AS expected_months_to_be_appropriated,
  (mobs_in_between_due_dates - expected_appropriated_months) * (value_upfront_signatures/mobs_in_between_due_dates) AS expected_amount_to_be_appropriated,
  flag_has_activation AS has_activation,
  has_payment_advance,
  is_direct_billing,
  mobs_in_between_due_dates,
  min_dt_due AS dt_due_min,
  max_dt_due AS dt_due_max,
  month_last_day AS dt_month_last_day, 
  min_dt_paid AS dt_paid_min,
  max_dt_paid AS dt_paid_max,
  month_appropriation_start AS dt_month_appropriation_start,
  month_ref_creation AS dt_month_ref_creation,
  dt_contract_started,
  dt_ended,
  dt_created,
  NOW() AS ts_load
FROM 
  base
WHERE 
  has_payment_advance = true
