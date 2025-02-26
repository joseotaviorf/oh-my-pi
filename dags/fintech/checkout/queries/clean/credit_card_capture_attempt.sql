SELECT
    id,
    credit_card_id AS id_credit_card,
    code,
    token,
    status,
    capture_fail_reason,
    acquire_auth_code,
    acquire_name,
    acquire_nsu,
    acquire_tid,
    card_brand,
    installments,
    paid_amount,
    fixed_cost_of_transaction AS transaction_fixed_cost,
    installment_fee_amount,
    convenience_fee_amount,
    TIMESTAMP(paid_at) AS ts_paid,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_checkout_raw.credit_card_capture_attempt
