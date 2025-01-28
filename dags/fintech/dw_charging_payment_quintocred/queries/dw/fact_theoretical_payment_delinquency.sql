SELECT
  pl.sk_propose AS sk_propose_theoretical,
  p.id_array_delinquency AS sk_array_delinquency, 
  CASE 
    WHEN p.gateway_payment IS NOT NULL
      THEN p.sk_propose_charge
    WHEN p.gateway_delinquency IS NOT NULL 
    AND p.is_delinquency_active 
      THEN p.sk_propose_charge
    ELSE NULL
  END AS sk_propose_charge,
  p.sk_propose_payment,
  p.sk_transaction,
  p.sk_propose_delinquency,
  p.sk_delinquency,
  CASE 
    WHEN pl.month_start IS NOT NULL 
    AND COALESCE( p.gateway_payment, IF( p.is_delinquency_active, p.gateway_delinquency, NULL ) ) IS NULL 
      THEN 'vivendo de graça'
    WHEN COALESCE( p.gateway_payment, IF( p.is_delinquency_active, p.gateway_delinquency, NULL ) ) IS NOT NULL 
      THEN COALESCE( p.gateway_payment, IF( p.is_delinquency_active, p.gateway_delinquency, NULL ) )
  END AS gateway_final,
  pl.annual_guarantee_renewal AS annual_timeline_renewal,
  pl.annual_guarantee_propose_aud AS annual_timeline_propose_aud,
  pl.annual_value_propose,
  pl.status_at_ref,
  pl.mob_of_life,
  pl.mob_of_death,
  p.status_payment,
  IF( p.gateway_payment IS NULL, 'sem cobrança', p.gateway_payment) AS gateway_payment,
  p.billing_type_payment,
  p.status_delinquency,
  p.gateway_delinquency,
  p.value,
  p.value_paid,
  p.total_amount_delinquency,
  p.delinquency_monthly_value,
  p.delinquency_amount_paid_monthly,
  p.total_paid_delinquency, 
  p.open_amount_delinquency,
  p.total_open_amount_delinquency,
  p.discount_value_delinquency,
  p.total_discount_value_delinquency,
  p.is_delinquency_active,
  date_trunc( 'MONTH', p.dt_due_payment ) < date_trunc( 'MONTH', p.dt_created_payment ) AS is_retroactive_charging,
  p.is_overdue,
  p.value BETWEEN 
    pl.total_package_amount * 0.08 
    AND pl.total_package_amount * 0.12 
  AS is_payment_charge_correct_amount,
  CASE
    WHEN pl.monthly_guarantee_renewal > 0 
    AND coalesce( p.gateway_payment, IF( p.is_delinquency_active, p.gateway_delinquency, NULL ) ) IS NOT NULL 
      THEN TRUE
    WHEN IF( p.is_delinquency_active, DATE( p.month_charge ), NULL ) IS NOT NULL
      THEN FALSE
  END AS is_charged_on_contract_period,
  p.is_delinquency_charge_related,
  pl.is_direct_billing,
  CASE 
    WHEN p.gateway_payment IS NOT NULL
      THEN p.month_charge
    WHEN p.gateway_delinquency IS NOT NULL
    AND p.is_delinquency_active 
      THEN p.month_charge
    ELSE NULL
  END AS month_charge,
  pl.dt_contract_started,
  pl.dt_ended,
  pl.month_chargeble,
  pl.monthly_guarantee_renewal AS monthly_timeline_renewal,
  pl.monthly_guarantee_renewal_corrected AS monthly_timeline_renewal_corrected,
  pl.monthly_guarantee_propose_aud AS monthly_timeline_propose_aud,
  pl.monthly_value_propose,
  pl.month_start AS month_propose_life,
  pl.is_corrected_robot,
  DATE(p.month_due_original) AS month_due_original ,
  DATE(p.month_delinquency_due) AS month_delinquency_due,
  DATE(p.dt_paid_payment) AS dt_paid_payment,
  p.dt_created_payment,
  p.dt_due_payment,
  DATE(p.dt_paid_delinquency) AS dt_paid_delinquency
FROM 
  dw_charging_payment_quintocred.fact_propose_timeline pl
FULL OUTER JOIN 
  dw_charging_payment_quintocred.fact_payment_delinquency p
  ON pl.sk_propose = p.sk_propose_charge
  AND pl.month_start = p.month_charge
