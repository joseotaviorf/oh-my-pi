SELECT
    sk_propose,
    client_cpf_cnpj,
    delay_range_due,
    due_amount,
    paid_amount,
    discount_amount,
    open_amount,
    pdd_percentage,
    pdd,
    dt_due,
    NOW() AS ts_snapshot,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    dw_velo.quintocred_aging_recurring_payment_no_renewal
