SELECT
    sk_propose,
    client_cpf_cnpj,
    delay_range,
    days_delay,
    due_amount,
    paid_amount,
    paid_amount_2,
    open_amount,
    open_amount_termination,
    open_amount_guarantee,
    discount_value,
    is_contract_active,
    dt_contract_started,
    dt_analyst_annulment_input,
    NOW() AS ts_snapshot,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    dw_velo.quintocred_aging_occurrence
