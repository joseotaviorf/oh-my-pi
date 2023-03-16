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
    mova_invoice_theorical_amount AS invoice_theorical_amount,
    mova_invoice_paid_amount AS invoice_paid_amount,
    mova_invoice_theorical_fee AS invoice_theorical_fee,
    mova_invoice_paid_fee AS invoice_paid_fee,
    accrual_year_month,
    dt_due,
    dt_paid,
    dt_created,
    dt_signed,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.long_term_rental_anticipation