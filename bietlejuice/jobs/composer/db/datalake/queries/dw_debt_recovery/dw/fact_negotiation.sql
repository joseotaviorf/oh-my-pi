SELECT
    id_negotiation,
    id_contract,
    status,
    qt_installments,
    qt_installments_paid,
    total_expected_amout,
    paid_amount,
    negotiation_original_amount,
    negotiation_discount_amount,
    negotiation_fees_amount,
    breached_installment,
    is_contract_recurrent_debtor,
    has_renegotiated,
    dt_expected_end,
    ts_paid_all,
    ts_breach,
    ts_created_at,
    CURRENT_TIMESTAMP AS ts_load,
    EXTRACT(YEAR FROM current_date) AS year,
    EXTRACT(MONTH FROM current_date) AS month,
    EXTRACT(DAY FROM current_date) AS day
FROM
    datalake_debt_recovery.negotiation
