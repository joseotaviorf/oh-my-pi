SELECT
    MD5(CONCAT(id_contract_ebdb, id_invoice_entry, brokerage_share, accrual_year_month)) AS sk_brokerage_fee,
    id_contract_ebdb,
    brokerage_share,
    invoice_payment_status,
    first_rental_commission,
    agent_brokerage_share,
    brokerage_split_percentage,
    prod_theorical_amount,
    invoice_theorical_amount,
    invoice_paid_amount,
    accrual_year_month,
    dt_due,
    dt_paid,
    dt_contract_start,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.brokerage_fee
WHERE
  contract_guarantee IN (
    'SeguroFairfax',
    'PRO_GUARANTOR',
    'RentalDeposit',
    'Standalone'
  )
