SELECT
    id_lra AS sk_long_term_rental_anticipation,
    id_contract_ebdb,
    months_anticipated,
    installment,
    total_installments,
    total_rent,
    nbr_transactions_signed,
    prod_theorical_amount, 
    prod_theorical_fee,
    invoice_theorical_amount,
    invoice_paid_amount,
    accrual_year_month,
    dt_due,
    dt_paid,
    ts_created,
    ts_signed,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.long_term_rental_anticipation