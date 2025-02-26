SELECT
    id,
    credit_card_fee_id AS id_credit_card_fee,
    installments,
    convenience_fee_percentage,
    fee_percentage,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(disabled_at) AS ts_disabled
FROM
    datalake_checkout_raw.credit_card_fee_installment
