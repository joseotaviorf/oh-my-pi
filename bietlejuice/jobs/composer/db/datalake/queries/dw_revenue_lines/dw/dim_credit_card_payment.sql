SELECT
  id_ccp AS sk_credit_card_payment,
  id_contract_ebdb,
  status,
  brand_name,
  type_paid,
  installments,
  invoice_theorical_amount,
  invoice_paid_amount,
  invoice_paid_fee,
  accrual_year_month,
  dt_ccp_created,
  dt_due,
  dt_paid
FROM
    datalake_revenue_lines.credit_card_payment