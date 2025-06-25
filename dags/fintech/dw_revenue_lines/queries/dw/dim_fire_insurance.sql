SELECT
  id_contract as sk_contract,
  id_invoice as sk_invoice,
  accrual_year_month,
  comission_factor,
  guarantee,
  origin_fact,
  raw_payment_amount,
  rent,
  revenue_comission,
  dt_annulment,
  dt_start,
  NOW() AS ts_load
FROM
  datalake_revenue_lines.fire_insurance
