SELECT
    MONOTONICALLY_INCREASING_ID() AS sk_management_fee,
    id_contract_ebdb,
    management_fee_share,
    payment_status,
    monthly_administration_fee,
    administration_split_percentage,
    prod_theorical_amount,
    invoice_theorical_amount,
    invoice_paid_amount,
    accrual_year_month,
    dt_due,
    dt_paid,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.management_fee
