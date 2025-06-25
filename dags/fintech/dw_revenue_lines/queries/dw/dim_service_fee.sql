SELECT
    MONOTONICALLY_INCREASING_ID() AS sk_service_fee,
    id_contract_ebdb,
    invoice_payment_status,
    tenant_service_fee,
    prod_theorical_amount,
    invoice_theorical_amount,
    invoice_paid_amount,
    accrual_year_month,
    dt_due,
    dt_paid,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.service_fee
