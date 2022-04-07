SELECT
    id_guarantee AS sk_rental_guarantee,
    id_contract_ebdb,
    id_charge,
    guarantee_status,
    charge_status,
    charge_type,
    total_installments,
    installment_number,
    monthly_revenue,
    accrual_year_month,
    ts_guarantee_created,
    ts_charge_created,
    ts_guarantee_paid,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.rental_guarantee