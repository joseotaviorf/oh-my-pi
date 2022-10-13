SELECT
    id_contract AS sk_contract_revenue,
    id_lpf_rent AS sk_late_payments_rent,
    id_lpf_condo AS sk_late_payments_condo,   
    id_mra AS sk_month_rental_anticipation,
    id_lra AS sk_long_term_rental_anticipation,
    id_bfi AS sk_brokerage_finance,
    id_reservation AS sk_reservation,
    id_ccp AS sk_credit_card_payment,
    id_guarantee AS sk_rental_guarantee,
    id_guarantee_charge AS sk_rental_guarantee_charge,
    month_start AS sk_month_start,
    due_monthly_revenue,
    paid_monthly_revenue,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.contract_revenues