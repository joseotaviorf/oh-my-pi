SELECT
    id_contract AS sk_contract,
    id_guarantee AS sk_guarantee,
    id_proposal AS sk_proposal,
    accrual_year_month,
    number_payments,
    origin_fact,
    raw_payment_amount,
    revenue_qa,
    guarantee_type,
    ts_guarantee_created,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.rental_guarantee