SELECT
    id_mra AS sk_month_rental_anticipation,
    id_contract_ebdb,
    nbr_transactions_accepted,
    prod_theorical_amount,
    prod_theorical_fee,
    invoice_theorical_amount,
    invoice_theorical_fee,
    invoice_paid_amount,
    invoice_paid_fee,
    accrual_year_month,
    dt_created,
    dt_accepted,
    dt_first_accepted,
    dt_due_fee,
    dt_paid_fee
FROM
    datalake_revenue_lines.month_rental_anticipation